{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
module Events
  ( ensureKeybindingConsistency
  , onEvent
  )
where

import           Prelude ()
import           Prelude.MH

import           Brick
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Map as M
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Graphics.Vty as Vty
import           Lens.Micro.Platform ( (.=) )

import qualified Network.Mattermost.Endpoints as MM
import           Network.Mattermost.Exceptions ( mattermostErrorMessage )
import           Network.Mattermost.Lenses
import           Network.Mattermost.Types
import           Network.Mattermost.WebSocket

import           Connection
import           HelpTopics
import           State.Channels
import           State.Common
import           State.Flagging
import           State.Messages
import           State.Reactions
import           State.Users
import           Types
import           Types.Common
import           Types.KeyEvents

import           Events.ChannelScroll
import           Events.ChannelSelect
import           Events.DeleteChannelConfirm
import           Events.JoinChannel
import           Events.Keybindings
import           Events.LeaveChannelConfirm
import           Events.Main
import           Events.MessageSelect
import           Events.PostListOverlay
import           Events.ShowHelp
import           Events.UrlSelect
import           Events.UserListOverlay
import           Events.ViewMessage


onEvent :: ChatState -> BrickEvent Name MHEvent -> EventM Name (Next ChatState)
onEvent st ev = runMHEvent st (onEv >> fetchVisibleIfNeeded)
    where onEv = do case ev of
                      (AppEvent e) -> onAppEvent e
                      (VtyEvent e) -> onVtyEvent e
                      _ -> return ()

onAppEvent :: MHEvent -> MH ()
onAppEvent RefreshWebsocketEvent = connectWebsockets
onAppEvent WebsocketDisconnect = do
  csConnectionStatus .= Disconnected
  disconnectChannels
onAppEvent WebsocketConnect = do
  csConnectionStatus .= Connected
  refreshChannelsAndUsers
  refreshClientConfig
onAppEvent BGIdle     = csWorkerIsBusy .= Nothing
onAppEvent (BGBusy n) = csWorkerIsBusy .= Just n
onAppEvent (WSEvent we) =
  handleWSEvent we
onAppEvent (RespEvent f) = f
onAppEvent (WebsocketParseError e) = do
  let msg = "A websocket message could not be parsed:\n  " <>
            T.pack e <>
            "\nPlease report this error at https://github.com/matterhorn-chat/matterhorn/issues"
  mhError $ GenericError msg
onAppEvent (IEvent e) = do
  handleIEvent e

handleIEvent :: InternalEvent -> MH ()
handleIEvent (DisplayError e) = postErrorMessage' $ formatError e
handleIEvent (LoggingStarted path) =
    postInfoMessage $ "Logging to " <> T.pack path
handleIEvent (LogDestination dest) =
    case dest of
        Nothing ->
            postInfoMessage "Logging is currently disabled. Enable it with /log-start."
        Just path ->
            postInfoMessage $ T.pack $ "Logging to " <> path
handleIEvent (LogSnapshotSucceeded path) =
    postInfoMessage $ "Log snapshot written to " <> T.pack path
handleIEvent (LoggingStopped path) =
    postInfoMessage $ "Stopped logging to " <> T.pack path
handleIEvent (LogStartFailed path err) =
    postErrorMessage' $ "Could not start logging to " <> T.pack path <>
                        ", error: " <> T.pack err
handleIEvent (LogSnapshotFailed path err) =
    postErrorMessage' $ "Could not write log snapshot to " <> T.pack path <>
                        ", error: " <> T.pack err

formatError :: MHError -> T.Text
formatError (GenericError msg) =
    msg
formatError (NoSuchChannel chan) =
    T.pack $ "No such channel: " <> show chan
formatError (NoSuchUser user) =
    T.pack $ "No such user: " <> show user
formatError (AmbiguousName name) =
    (T.pack $ "The input " <> show name <> " matches both channels ") <>
    "and users. Try using '" <> userSigil <> "' or '" <>
    normalChannelSigil <> "' to disambiguate."
formatError (ServerError e) =
    mattermostErrorMessage e
formatError (ClipboardError msg) =
    msg
formatError (ConfigOptionMissing opt) =
    T.pack $ "Config option " <> show opt <> " missing"
formatError (ProgramExecutionFailed progName logPath) =
    T.pack $ "An error occurred when running " <> show progName <>
             "; see " <> show logPath <> " for details."
formatError (NoSuchScript name) =
    "No script named " <> name <> " was found"
formatError (NoSuchHelpTopic topic) =
    let knownTopics = ("  - " <>) <$> helpTopicName <$> helpTopics
    in "Unknown help topic: `" <> topic <> "`. " <>
       (T.unlines $ "Available topics are:" : knownTopics)
formatError (AsyncErrEvent e) =
    "An unexpected error has occurred! The exception encountered was:\n  " <>
    T.pack (show e) <>
    "\nPlease report this error at https://github.com/matterhorn-chat/matterhorn/issues"

toplevelKeybindings :: KeyConfig -> [Keybinding]
toplevelKeybindings = mkKeybindings
    [ mkKb DumpStateEvent
        "Dump the application state to disk for debugging"
        dumpState
    , mkKb VtyRefreshEvent
        "Redraw the screen"
        (do vty <- mh getVtyHandle
            liftIO $ Vty.refresh vty)
    ]

dumpState :: MH ()
dumpState = do
    st <- get
    rs <- mh getRenderState
    ds <- mh $ Vty.displayBounds =<< (Vty.outputIface <$> getVtyHandle)
    let sstate = SerializedState { serializedChatState = st
                                 , serializedRenderState = rs
                                 , serializedWindowSize = ds
                                 }
    liftIO $ BSL.writeFile "/tmp/matterhorn_state.json" $ A.encode sstate

onVtyEvent :: Vty.Event -> MH ()
onVtyEvent ev = do
    -- Even if we aren't showing the help UI when a resize occurs, we
    -- need to invalidate its cache entry anyway in case the new size
    -- differs from the cached size.
    case ev of
        (Vty.EvResize _ _) -> mh invalidateCache
        _ -> return ()

    let fallback e = do
            mode <- gets appMode
            case mode of
                Main                       -> onEventMain e
                ShowHelp _                 -> onEventShowHelp e
                ChannelSelect              -> onEventChannelSelect e
                UrlSelect                  -> onEventUrlSelect e
                LeaveChannelConfirm        -> onEventLeaveChannelConfirm e
                JoinChannel                -> onEventJoinChannel e
                ChannelScroll              -> onEventChannelScroll e
                MessageSelect              -> onEventMessageSelect e
                MessageSelectDeleteConfirm -> onEventMessageSelectDeleteConfirm e
                DeleteChannelConfirm       -> onEventDeleteChannelConfirm e
                PostListOverlay _          -> onEventPostListOverlay e
                UserListOverlay            -> onEventUserListOverlay e
                ViewMessage                -> onEventViewMessage e

    handleKeyboardEvent toplevelKeybindings fallback ev

handleWSEvent :: WebsocketEvent -> MH ()
handleWSEvent we = do
    myId <- gets myUserId
    myTId <- gets myTeamId
    case weEvent we of
        WMPosted
            | Just p <- wepPost (weData we) ->
                when (wepTeamId (weData we) == Just myTId ||
                      wepTeamId (weData we) == Nothing) $ do
                    -- If the message is a header change, also update
                    -- the channel metadata.
                    let wasMentioned = case wepMentions (weData we) of
                          Just lst -> myId `Set.member` lst
                          _ -> False
                    addNewPostedMessage $ RecentPost p wasMentioned
            | otherwise -> return ()

        WMPostEdited
            | Just p <- wepPost (weData we) -> editMessage p
            | otherwise -> return ()

        WMPostDeleted
            | Just p <- wepPost (weData we) -> deleteMessage p
            | otherwise -> return ()

        WMStatusChange
            | Just status <- wepStatus (weData we)
            , Just uId <- wepUserId (weData we) ->
                setUserStatus uId status
            | otherwise -> return ()

        WMUserAdded
            | Just cId <- webChannelId (weBroadcast we) ->
                when (wepUserId (weData we) == Just myId &&
                      wepTeamId (weData we) == Just myTId) $
                    handleChannelInvite cId
            | otherwise -> return ()

        WMNewUser
            | Just uId <- wepUserId $ weData we -> handleNewUsers (Seq.singleton uId)
            | otherwise -> return ()

        WMUserRemoved
            | Just cId <- wepChannelId (weData we) ->
                when (webUserId (weBroadcast we) == Just myId) $
                    removeChannelFromState cId
            | otherwise -> return ()

        WMTyping
            | Just uId <- wepUserId $ weData we
            , Just cId <- webChannelId (weBroadcast we) -> handleTypingUser uId cId
            | otherwise -> return ()

        WMChannelDeleted
            | Just cId <- wepChannelId (weData we) ->
                when (webTeamId (weBroadcast we) == Just myTId) $
                    removeChannelFromState cId
            | otherwise -> return ()

        WMDirectAdded
            | Just cId <- webChannelId (weBroadcast we) -> handleChannelInvite cId
            | otherwise -> return ()

        -- An 'ephemeral message' is just Mattermost's version of our
        -- 'client message'. This can be a little bit wacky, e.g.
        -- if the user types '/shortcuts' in the browser, we'll get
        -- an ephemeral message even in MatterHorn with the browser
        -- shortcuts, but it's probably a good idea to handle these
        -- messages anyway.
        WMEphemeralMessage
            | Just p <- wepPost $ weData we -> postInfoMessage (sanitizeUserText $ p^.postMessageL)
            | otherwise -> return ()

        WMPreferenceChanged
            | Just prefs <- wepPreferences (weData we) ->
                mapM_ applyPreferenceChange prefs
            | otherwise -> return ()

        WMPreferenceDeleted
            | Just pref <- wepPreferences (weData we)
            , Just fps <- mapM preferenceToFlaggedPost pref ->
              forM_ fps $ \f ->
                  updateMessageFlag (flaggedPostId f) False
            | otherwise -> return ()

        WMReactionAdded
            | Just r <- wepReaction (weData we)
            , Just cId <- webChannelId (weBroadcast we) -> addReactions cId [r]
            | otherwise -> return ()

        WMReactionRemoved
            | Just r <- wepReaction (weData we)
            , Just cId <- webChannelId (weBroadcast we) -> removeReaction r cId
            | otherwise -> return ()

        WMChannelViewed
            | Just cId <- wepChannelId $ weData we -> refreshChannelById cId
            | otherwise -> return ()

        WMChannelUpdated
            | Just cId <- webChannelId $ weBroadcast we ->
                when (webTeamId (weBroadcast we) == Just myTId) $ refreshChannelById cId
            | otherwise -> return ()

        WMGroupAdded
            | Just cId <- webChannelId (weBroadcast we) -> handleChannelInvite cId
            | otherwise -> return ()

        -- We are pretty sure we should do something about these:
        WMAddedToTeam -> return ()

        -- We aren't sure whether there is anything we should do about
        -- these yet:
        WMUpdateTeam -> return ()
        WMTeamDeleted -> return ()
        WMUserUpdated -> return ()
        WMLeaveTeam -> return ()

        -- We deliberately ignore these events:
        WMChannelCreated -> return ()
        WMEmojiAdded -> return ()
        WMWebRTC -> return ()
        WMHello -> return ()
        WMAuthenticationChallenge -> return ()
        WMUserRoleUpdated -> return ()
        WMPluginStatusesChanged -> return ()
        WMPluginEnabled -> return ()
        WMPluginDisabled -> return ()

-- | Given a configuration, we want to check it for internal
-- consistency (i.e. that a given keybinding isn't associated with
-- multiple events which both need to get generated in the same UI
-- mode) and also for basic usability (i.e. we shouldn't be binding
-- events which can appear in the main UI to a key like @e@, which
-- would prevent us from being able to type messages containing an @e@
-- in them!
ensureKeybindingConsistency :: KeyConfig -> Either String ()
ensureKeybindingConsistency kc = do
    mapM_ checkGroup allBindings
    checkToplevelBindings
  where
    checkToplevelBindings = do
        forM_ (toplevelKeybindings kc) $ \kb -> do
            -- Is the event for this binding also bound to anything in
            -- other modes? If so, is it bound to a different key?
            case kbBindingInfo kb of
                Nothing -> return ()
                Just ev -> do
                    let matches = filter ((== (eventToBinding $ kbEvent kb)) . fst) $ concat allBindings
                        conflicts = filter ((/= ev). snd . snd) matches
                    when (not $ null conflicts) $ do
                        Left $ "The binding " <> (T.unpack $ ppBinding $ eventToBinding $ kbEvent kb) <>
                               " is bound to multiple events: " <>
                               (intercalate ", " $ ppEvent <$>
                                   (ev : (snd <$> snd <$> conflicts)))

    -- This is a list of lists, grouped by keybinding, of all the
    -- keybinding/event associations that are going to be used with
    -- the provided key configuration.
    allBindings = groupWith fst $ concat
      [ case M.lookup ev kc of
          Nothing -> zip (defaultBindings ev) (repeat (False, ev))
          Just (BindingList bs) -> zip bs (repeat (True, ev))
          Just Unbound -> []
      | ev <- allEvents
      ]

    -- the invariant here is that each call to checkGroup is made with
    -- a list where the first element of every list is the same
    -- binding. The Bool value in these is True if the event was
    -- associated with the binding by the user, and False if it's a
    -- Matterhorn default.
    checkGroup :: [(Binding, (Bool, KeyEvent))] -> Either String ()
    checkGroup [] = error "[ensureKeybindingConsistency: unreachable]"
    checkGroup evs@((b, _):_) = do

      -- We find out which modes an event can be used in and then
      -- invert the map, so this is a map from mode to the events
      -- contains which are bound by the binding included above.
      let modesFor :: M.Map String [(Bool, KeyEvent)]
          modesFor = M.unionsWith (++)
            [ M.fromList [ (m, [(i, ev)]) | m <- modeMap ev ]
            | (_, (i, ev)) <- evs
            ]

      -- If there is ever a situation where the same key is bound to
      -- two events which can appear in the same mode, then we want to
      -- throw an error, and also be informative about why. It is
      -- still okay to bind the same key to two events, so long as
      -- those events never appear in the same UI mode.
      forM_ (M.assocs modesFor) $ \ (_, vs) ->
         when (length vs > 1) $
           Left $ concat $
             "Multiple overlapping events bound to `" :
             T.unpack (ppBinding b) :
             "`:\n" :
             concat [ [ " - `"
                      , T.unpack (keyEventName ev)
                      , "` "
                      , if isFromUser
                          then "(via user override)"
                          else "(matterhorn default)"
                      , "\n"
                      ]
                    | (isFromUser, ev) <- vs
                    ]

      -- check for overlap a set of built-in keybindings when we're in
      -- a mode where the user is typing. (These are perfectly fine
      -- when we're in other modes.)
      when ("main" `M.member` modesFor && isBareBinding b) $ do
        Left $ concat $
          [ "The keybinding `"
          , T.unpack (ppBinding b)
          , "` is bound to the "
          , case map (ppEvent . snd . snd) evs of
              [] -> error "unreachable"
              [e] -> "event " ++ e
              es  -> "events " ++ intercalate " and " es
          , "\n"
          , "This is probably not what you want, as it will interfere\n"
          , "with the ability to write messages!\n"
          ]

    -- Events get some nice formatting!
    ppEvent ev = "`" ++ T.unpack (keyEventName ev) ++ "`"

    -- This check should get more nuanced, but as a first
    -- approximation, we shouldn't bind to any bare character key in
    -- the main mode.
    isBareBinding (Binding [] (Vty.KChar {})) = True
    isBareBinding _ = False

    -- We generate the which-events-are-valid-in-which-modes map from
    -- our actual keybinding set, so this should never get out of date.
    modeMap ev =
      [ mode
      | (mode, bindings) <- modeMaps
      , any (bindingHasEvent ev) bindings
      ]

    bindingHasEvent ev (KB _ _ _ (Just ev')) = ev == ev'
    bindingHasEvent _ _ = False

    modeMaps = [ ("main" :: String, mainKeybindings kc)
               , ("help screen", helpKeybindings kc)
               , ("channel select", channelSelectKeybindings kc)
               , ("url select", urlSelectKeybindings kc)
               , ("channel scroll", channelScrollKeybindings kc)
               , ("message select", messageSelectKeybindings kc)
               , ("post list overlay", postListOverlayKeybindings kc)
               ]

-- | Refresh client-accessible server configuration information. This
-- is usually triggered when a reconnect event for the WebSocket to the
-- server occurs.
refreshClientConfig :: MH ()
refreshClientConfig = do
    session <- getSession
    doAsyncWith Preempt $ do
        cfg <- MM.mmGetClientConfiguration (Just "old") session
        return (csClientConfig .= Just cfg)
