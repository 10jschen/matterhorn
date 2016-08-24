{-# LANGUAGE RecordWildCards #-}

module Main where

import           Brick
import           Brick.Widgets.Border
import           Brick.Widgets.Edit ( renderEditor
                                    , getEditContents
                                    , handleEditorEvent
                                    , applyEdit
                                    )
import qualified Control.Concurrent.Chan as Chan
import           Control.Monad (void)
import           Control.Monad.IO.Class (liftIO)
import           Data.Default (def)
import           Data.Text.Zipper (clearZipper)
import qualified Graphics.Vty as Vty
import           Lens.Micro.Platform

import           Network.Mattermost
import           Network.Mattermost.Lenses
import           Network.Mattermost.WebSocket
import           Network.Mattermost.WebSocket.Types

import           Config
import           State

data Event
  = VtyEvent Vty.Event
  | WSEvent WebsocketEvent

main :: IO ()
main = do
  config <- getConfig
  st <- setupState config

  eventChan <- Chan.newChan
  let shunt e = Chan.writeChan eventChan (WSEvent e)

  mmWithWebSocket (st^.csConn) (st^.csTok) shunt $ \c -> do
    void $ customMain (Vty.mkVty def) eventChan (app config) st

app :: Config -> App ChatState Event Int
app config = App
  { appDraw = chatDraw
  , appChooseCursor = \ _ (l:_) -> Just l
  , appHandleEvent = onEvent config
  , appStartEvent = \ s -> return s
  , appAttrMap = \ _ -> def
  , appLiftVtyEvent = VtyEvent
  }

chatDraw :: ChatState -> [Widget Int]
chatDraw st =
  let cId = currChannel st
      chnName = getChannelName cId st
      msgs = getMessageListing cId st
      chatText = vBox [ str (u ++ ": " ++ m)
                      | (u, m) <- msgs
                      ]
      userCmd  = (str "> " <+> renderEditor True (st^.cmdLine))
      chanList = vBox $
        [ str (i ++ "#" ++ n)
        | n <- (st ^. csNames . cnChans)
        , let i = if n == chnName then "+" else " "
        ] ++
        [ str (" @" ++ n)
        | n <- (st ^. csNames . cnUsers)
        ]
  in [ (border chanList <+> (border (padRight Max (str ("#" ++ chnName)))
                             <=> border (viewport 0 Vertical chatText)))
        <=> border userCmd
     ]
--  in [ border (padRight Max (str ("#" ++ chnName))) <=>
--       (border chanList <+> border (viewport 0 Vertical chatText)) <=>
--       border userCmd
--     ]

onEvent :: Config -> ChatState -> Event -> EventM Int (Next ChatState)
onEvent _ st (VtyEvent (Vty.EvKey Vty.KEsc [])) = halt st
onEvent _ st (VtyEvent (Vty.EvKey Vty.KRight [])) =
  continue (nextChannel st)
onEvent _ st (VtyEvent (Vty.EvKey Vty.KLeft [])) =
  continue (prevChannel st)
onEvent _ st (VtyEvent (Vty.EvKey Vty.KEnter [])) = do
  let (line:_) = getEditContents (st^.cmdLine)
  let st' = st & cmdLine %~ applyEdit clearZipper
  case line of
    ('/':cmd) -> handleCmd cmd st'
    _         -> do
      liftIO (sendMessage st' line)
      continue st'
onEvent _ st (VtyEvent e) = do
  editor <- handleEditorEvent e (st^.cmdLine)
  continue (st & cmdLine .~ editor)
onEvent c st (WSEvent we) = do
  case weAction we of
    WMPosted -> case wepPost (weProps we) of
      Just p  -> do
        let Just usr = userProfileUsername <$> (st ^. usrMap . at (postUserId p))
            msg = postMessage p
        liftIO $ runMessageCallback c usr msg
        continue $ addMessage p st
      Nothing -> continue st
    WMPostEdited -> case wepPost (weProps we) of
      Just p  -> continue $ editMessage p st
      Nothing -> continue st
    WMPostDeleted -> case wepPost (weProps we) of
      Just p  -> continue $ editMessage p { postMessage = "[deleted]" } st
      Nothing -> continue st
    _ -> continue st

sendMessage :: ChatState -> String -> IO ()
sendMessage st msg = do
  let myId   = st^.csMe.userIdL
      chanId = currChannel st
      teamId = st^.csMyTeam.teamIdL
  pendingPost <- mkPendingPost msg myId chanId
  _ <- mmPost (st^.csConn) (st^.csTok) teamId pendingPost
  return ()

handleCmd :: String -> ChatState -> EventM Int (Next ChatState)
handleCmd cmd st = case words cmd of
  ["quit"] -> halt st
  ["right"] -> continue (nextChannel st)
  ["left"] -> continue (prevChannel st)
  ["chan", ch] -> continue (setFocus ch st)
  _ -> continue st

{-
handleInput :: StateRef -> MMWebSocket -> IO ()
handleInput st ws = do
  ln <- getLine
  case words ln of
    ["show", chan] -> do
      ChatState { _chnMap = cs } <- readIORef st
      case [ c | c <- HM.elems cs, channelName c == chan ] of
        c:_ -> do
          ms <- getMessageListing (channelId c) st
          forM_ ms $ \ (u, m) -> do
            putStrLn ("@" ++ u ++ ":  " ++ m)
          handleInput st ws
        _ -> do
          putStrLn ("cannot find " ++ chan)
          handleInput st ws
    ["quit"] -> do
      mmCloseWebSocket ws
    cmd -> do
      putStrLn ("I don't know how to " ++ unwords cmd)
      handleInput st ws
-}
