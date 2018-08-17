{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RecordWildCards #-}
module State.Editing
  ( requestSpellCheck
  , editingKeybindings
  , toggleMessagePreview
  , toggleMultilineEditing
  , invokeExternalEditor
  , handlePaste
  , handleEditingInput
  )
where

import           Prelude ()
import           Prelude.MH

import           Brick.Widgets.Edit ( Editor, applyEdit , handleEditorEvent
                                    , getEditContents, editContentsL )
import qualified Codec.Binary.UTF8.Generic as UTF8
import           Control.Arrow
import qualified Control.Concurrent.STM as STM
import qualified Data.ByteString as BS
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Zipper as Z
import qualified Data.Text.Zipper.Generic.Words as Z
import           Data.Time ( getCurrentTime )
import           Graphics.Vty ( Event(..), Key(..), Modifier(..) )
import           Lens.Micro.Platform ( (%=), (.=), (.~), to )
import qualified System.Environment as Sys
import qualified System.Exit as Sys
import qualified System.IO as Sys
import qualified System.IO.Temp as Sys
import qualified System.Process as Sys
import           Text.Aspell ( AspellResponse(..), mistakeWord, askAspell )

import           Network.Mattermost.Types (Post(..))

import           Config
import           Events.Keybindings
import           State.Common
import           Types
import           Types.Common ( sanitizeChar, sanitizeUserText' )


startMultilineEditing :: MH ()
startMultilineEditing = csEditState.cedMultiline .= True

toggleMultilineEditing :: MH ()
toggleMultilineEditing = csEditState.cedMultiline %= not

invokeExternalEditor :: MH ()
invokeExternalEditor = do
    -- If EDITOR is in the environment, write the current message to a
    -- temp file, invoke EDITOR on it, read the result, remove the temp
    -- file, and update the program state.
    --
    -- If EDITOR is not present, fall back to 'vi'.
    mEnv <- liftIO $ Sys.lookupEnv "EDITOR"
    let editorProgram = maybe "vi" id mEnv

    mhSuspendAndResume $ \ st -> do
      Sys.withSystemTempFile "matterhorn_editor.tmp" $ \tmpFileName tmpFileHandle -> do
        -- Write the current message to the temp file
        Sys.hPutStr tmpFileHandle $ T.unpack $ T.intercalate "\n" $
            getEditContents $ st^.csEditState.cedEditor
        Sys.hClose tmpFileHandle

        -- Run the editor
        status <- Sys.system (editorProgram <> " " <> tmpFileName)

        -- On editor exit, if exited with zero status, read temp file.
        -- If non-zero status, skip temp file read.
        case status of
            Sys.ExitSuccess -> do
                tmpBytes <- BS.readFile tmpFileName
                case T.decodeUtf8' tmpBytes of
                    Left _ -> do
                        postErrorMessageIO "Failed to decode file contents as UTF-8" st
                    Right t -> do
                        let tmpLines = T.lines $ sanitizeUserText' t
                        return $ st & csEditState.cedEditor.editContentsL .~ (Z.textZipper tmpLines Nothing)
                                    & csEditState.cedMultiline .~ (length tmpLines > 1)
            Sys.ExitFailure _ -> return st

toggleMessagePreview :: MH ()
toggleMessagePreview = csShowMessagePreview %= not

handlePaste :: BS.ByteString -> MH ()
handlePaste bytes = do
  let pasteStr = T.pack (UTF8.toString bytes)
  csEditState.cedEditor %= applyEdit (Z.insertMany (sanitizeUserText' pasteStr))
  contents <- use (csEditState.cedEditor.to getEditContents)
  case length contents > 1 of
      True -> startMultilineEditing
      False -> return ()

editingPermitted :: ChatState -> Bool
editingPermitted st =
    (length (getEditContents $ st^.csEditState.cedEditor) == 1) ||
    st^.csEditState.cedMultiline

editingKeybindings :: [Keybinding]
editingKeybindings =
  let kb desc ev mote = KB desc ev mote Nothing in
  map withUserTypingAction
  [ kb "Transpose the final two characters"
    (EvKey (KChar 't') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.transposeChars
    csEditState.cedCompleter .= Nothing
  , kb "Go to the start of the current line"
    (EvKey (KChar 'a') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.gotoBOL
  , kb "Go to the end of the current line"
    (EvKey (KChar 'e') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.gotoEOL
  , kb "Delete the character at the cursor"
    (EvKey (KChar 'd') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.deleteChar
    csEditState.cedCompleter .= Nothing
  , kb "Delete from the cursor to the start of the current line"
    (EvKey (KChar 'u') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.killToBOL
    csEditState.cedCompleter .= Nothing
  , kb "Move one character to the right"
    (EvKey (KChar 'f') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.moveRight
    csEditState.cedCompleter .= Nothing
  , kb "Move one character to the left"
    (EvKey (KChar 'b') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.moveLeft
    csEditState.cedCompleter .= Nothing
  , kb "Move one word to the right"
    (EvKey (KChar 'f') [MMeta]) $ do
    csEditState.cedEditor %= applyEdit Z.moveWordRight
    csEditState.cedCompleter .= Nothing
  , kb "Move one word to the left"
    (EvKey (KChar 'b') [MMeta]) $ do
    csEditState.cedEditor %= applyEdit Z.moveWordLeft
    csEditState.cedCompleter .= Nothing
  , kb "Delete the word to the left of the cursor"
    (EvKey KBS [MMeta]) $ do
    csEditState.cedEditor %= applyEdit Z.deletePrevWord
    csEditState.cedCompleter .= Nothing
  , kb "Delete the word to the left of the cursor"
    (EvKey (KChar 'w') [MCtrl]) $ do
    csEditState.cedEditor %= applyEdit Z.deletePrevWord
    csEditState.cedCompleter .= Nothing
  , kb "Delete the word to the right of the cursor"
    (EvKey (KChar 'd') [MMeta]) $ do
    csEditState.cedEditor %= applyEdit Z.deleteWord
    csEditState.cedCompleter .= Nothing
  , kb "Move the cursor to the beginning of the input"
    (EvKey KHome []) $ do
    csEditState.cedEditor %= applyEdit gotoHome
  , kb "Move the cursor to the end of the input"
    (EvKey KEnd []) $ do
    csEditState.cedEditor %= applyEdit gotoEnd
  , kb "Kill the line to the right of the current position and copy it"
    (EvKey (KChar 'k') [MCtrl]) $ do
      z <- use (csEditState.cedEditor.editContentsL)
      let restOfLine = Z.currentLine (Z.killToBOL z)
      csEditState.cedYankBuffer .= restOfLine
      csEditState.cedEditor %= applyEdit Z.killToEOL
      csEditState.cedCompleter .= Nothing
  , kb "Paste the current buffer contents at the cursor"
    (EvKey (KChar 'y') [MCtrl]) $ do
      buf <- use (csEditState.cedYankBuffer)
      csEditState.cedEditor %= applyEdit (Z.insertMany buf)
      csEditState.cedCompleter .= Nothing
  ]
  where
    withUserTypingAction (KB {..}) =
      KB kbDescription kbEvent
         (kbAction >> sendUserTypingAction)
         kbBindingInfo

handleEditingInput :: Event -> MH ()
handleEditingInput e = do
    -- Only handle input events to the editor if we permit editing:
    -- if multiline mode is off, or if there is only one line of text
    -- in the editor. This means we skip input this catch-all handler
    -- if we're *not* in multiline mode *and* there are multiple lines,
    -- i.e., we are showing the user the status message about the
    -- current editor state and editing is not permitted.

    smartBacktick <- use (csResources.crConfiguration.to configSmartBacktick)
    let smartChars = "*`_"
    st <- use id
    case lookupKeybinding e editingKeybindings of
      Just kb | editingPermitted st -> kbAction kb
      _ -> do
        case e of
          -- Not editing; backspace here means cancel multi-line message
          -- composition
          EvKey KBS [] | (not $ editingPermitted st) ->
            csEditState.cedEditor %= applyEdit Z.clearZipper

          -- Backspace in editing mode with smart pair insertion means
          -- smart pair removal when possible
          EvKey KBS [] | editingPermitted st && smartBacktick ->
              let backspace = csEditState.cedEditor %= applyEdit Z.deletePrevChar
              in case cursorAtOneOf smartChars (st^.csEditState.cedEditor) of
                  Nothing -> backspace
                  Just ch ->
                      -- Smart char removal:
                      if | (cursorAtChar ch $ applyEdit Z.moveLeft $ st^.csEditState.cedEditor) &&
                           (cursorIsAtEnd $ applyEdit Z.moveRight $ st^.csEditState.cedEditor) ->
                             csEditState.cedEditor %= applyEdit (Z.deleteChar >>> Z.deletePrevChar)
                         | otherwise -> backspace

          EvKey (KChar ch) []
            | editingPermitted st && smartBacktick && ch `elem` smartChars ->
              -- Smart char insertion:
              let doInsertChar = do
                    csEditState.cedEditor %= applyEdit (Z.insertChar ch)
                    sendUserTypingAction
              in if | (editorEmpty $ st^.csEditState.cedEditor) ||
                         ((cursorAtChar ' ' (applyEdit Z.moveLeft $ st^.csEditState.cedEditor)) &&
                          (cursorIsAtEnd $ st^.csEditState.cedEditor)) ->
                        csEditState.cedEditor %= applyEdit (Z.insertMany (T.pack $ ch:ch:[]) >>> Z.moveLeft)
                    | (cursorAtChar ch $ st^.csEditState.cedEditor) &&
                      (cursorIsAtEnd $ applyEdit Z.moveRight $ st^.csEditState.cedEditor) ->
                        csEditState.cedEditor %= applyEdit Z.moveRight
                    | otherwise -> doInsertChar
            | editingPermitted st -> do
              csEditState.cedEditor %= applyEdit (Z.insertMany (sanitizeChar ch))
              sendUserTypingAction
          _ | editingPermitted st -> do
              mhHandleEventLensed (csEditState.cedEditor) handleEditorEvent e
              sendUserTypingAction
            | otherwise -> return ()

        csEditState.cedCompleter .= Nothing

    liftIO $ resetSpellCheckTimer $ st^.csEditState

-- | Send the user_typing action to the server asynchronously, over the connected websocket.
-- | If the websocket is not connected, drop the action silently.
sendUserTypingAction :: MH ()
sendUserTypingAction = do
  st <- use id
  when (configShowTypingIndicator (st^.csResources.crConfiguration)) $
    case st^.csConnectionStatus of
      Connected -> do
        let pId = case st^.csEditState.cedEditMode of
                    Replying _ post -> Just $ postId post
                    _               -> Nothing
        liftIO $ do
          now <- getCurrentTime
          let action = UserTyping now (st^.csCurrentChannelId) pId
          STM.atomically $ STM.writeTChan (st^.csResources.crMutable.mutWebsocketActionChan) action
      Disconnected -> return ()

-- Kick off an async request to the spell checker for the current editor
-- contents.
requestSpellCheck :: MH ()
requestSpellCheck = do
    st <- use id
    case st^.csEditState.cedSpellChecker of
        Nothing -> return ()
        Just (checker, _) -> do
            -- Get the editor contents.
            contents <- getEditContents <$> use (csEditState.cedEditor)
            doAsyncWith Preempt $ do
                -- For each line in the editor, submit an aspell request.
                let query = concat <$> mapM (askAspell checker) contents
                    postMistakes :: [AspellResponse] -> MH ()
                    postMistakes responses = do
                        let getMistakes AllCorrect = []
                            getMistakes (Mistakes ms) = mistakeWord <$> ms
                            allMistakes = S.fromList $ concat $ getMistakes <$> responses
                        csEditState.cedMisspellings .= allMistakes

                tryMM query (return . postMistakes)

editorEmpty :: Editor Text a -> Bool
editorEmpty e = cursorIsAtEnd e &&
                cursorIsAtBeginning e

cursorIsAtEnd :: Editor Text a -> Bool
cursorIsAtEnd e =
    let col = snd $ Z.cursorPosition z
        curLine = Z.currentLine z
        z = e^.editContentsL
    in col == T.length curLine

cursorIsAtBeginning :: Editor Text a -> Bool
cursorIsAtBeginning e =
    let col = snd $ Z.cursorPosition z
        z = e^.editContentsL
    in col == 0

cursorAtOneOf :: [Char] -> Editor Text a -> Maybe Char
cursorAtOneOf [] _ = Nothing
cursorAtOneOf (c:cs) e =
    if cursorAtChar c e
    then Just c
    else cursorAtOneOf cs e

cursorAtChar :: Char -> Editor Text a -> Bool
cursorAtChar ch e =
    let col = snd $ Z.cursorPosition z
        curLine = Z.currentLine z
        z = e^.editContentsL
    in (T.singleton ch) `T.isPrefixOf` T.drop col curLine

gotoHome :: Z.TextZipper Text -> Z.TextZipper Text
gotoHome = Z.moveCursor (0, 0)

gotoEnd :: Z.TextZipper Text -> Z.TextZipper Text
gotoEnd z =
    let zLines = Z.getText z
        numLines = length zLines
        lastLineLength = T.length $ last zLines
    in if numLines > 0
       then Z.moveCursor (numLines - 1, lastLineLength) z
       else z
