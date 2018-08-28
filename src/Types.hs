{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
module Types
  ( ConnectionStatus(..)
  , HelpTopic(..)
  , MessageSelectState(..)
  , ProgramOutput(..)
  , MHEvent(..)
  , InternalEvent(..)
  , Name(..)
  , ChannelSelectMatch(..)
  , MatchValue(..)
  , StartupStateInfo(..)
  , MHError(..)
  , ConnectionInfo(..)
  , ciHostname
  , ciPort
  , ciUsername
  , ciPassword
  , Config(..)
  , HelpScreen(..)
  , PasswordSource(..)
  , MatchType(..)
  , EditMode(..)
  , Mode(..)
  , ChannelSelectPattern(..)
  , PostListContents(..)
  , AuthenticationException(..)
  , BackgroundInfo(..)
  , RequestChan
  , SerializedState(..)

  , MMNames
  , mkNames
  , refreshChannelZipper
  , getChannelIdsInOrder

  , trimChannelSigil

  , ChannelSelectState(..)
  , userMatches
  , channelMatches
  , channelSelectInput
  , selectedMatch
  , emptyChannelSelectState

  , ChatState
  , newState
  , csResources
  , csFocus
  , csCurrentChannel
  , csCurrentChannelId
  , csUrlList
  , csShowMessagePreview
  , csPostMap
  , csRecentChannel
  , csPostListOverlay
  , csUserListOverlay
  , csMyTeam
  , csMessageSelect
  , csJoinChannelList
  , csConnectionStatus
  , csWorkerIsBusy
  , csChannel
  , csChannels
  , csChannelSelectState
  , csEditState
  , csClientConfig
  , csLastJoinRequest
  , csViewedMessage
  , timeZone
  , whenMode
  , setMode
  , setMode'
  , appMode

  , ChatEditState
  , emptyEditState
  , cedYankBuffer
  , cedMisspellings
  , cedEditMode
  , cedCompleter
  , cedEditor
  , cedMultiline
  , cedInputHistory
  , cedInputHistoryPosition
  , cedLastChannelInput

  , PostListOverlayState
  , postListSelected
  , postListPosts

  , UserSearchScope(..)

  , UserListActivateType(..)

  , UserListOverlayState
  , userListSearchResults
  , userListSearchInput
  , userListSearchScope
  , userListSearching
  , userListRequestingMore
  , userListHasAllResults
  , userListActivateType

  , listFromUserSearchResults

  , ChatResources(..)
  , crUserPreferences
  , crTheme
  , crFlaggedPosts
  , crConfiguration
  , crSyntaxMap
  , crMutable

  , MutableResources(..)

  , getSession
  , getResourceSession

  , UserPreferences(UserPreferences)
  , userPrefShowJoinLeave
  , userPrefFlaggedPostList
  , userPrefGroupChannelPrefs

  , defaultUserPreferences
  , setUserPreferences

  , WebsocketAction(..)

  , Cmd(..)
  , commandName
  , CmdArgs(..)

  , MH
  , runMHEvent
  , mh
  , generateUUID
  , generateUUID_IO
  , mhSuspendAndResume
  , mhHandleEventLensed
  , St.gets
  , St.get
  , mhError

  , mhLog
  , mhGetIOLogger
  , LogContext(..)
  , withLogContext
  , withLogContextChannelId
  , getLogContext
  , LogMessage(..)
  , LogCommand(..)
  , LogCategory(..)

  , LogManager(..)
  , startLoggingToFile
  , stopLoggingToFile
  , requestLogSnapshot
  , requestLogDestination
  , sendLogMessage

  , requestQuit
  , clientPostToMessage
  , getMessageForPostId
  , getParentMessage
  , resetSpellCheckTimer
  , withChannel
  , withChannelOrDefault
  , userList
  , hasUnread
  , isMine
  , setUserStatus
  , myUser
  , myUserId
  , myTeamId
  , usernameForUserId
  , userIdForUsername
  , userByDMChannelName
  , userByUsername
  , channelIdByChannelName
  , channelIdByUsername
  , channelIdByName
  , channelByName
  , userById
  , allUserIds
  , allChannelNames
  , allUsernames
  , sortedUserList
  , removeChannelName
  , addChannelName
  , addNewUser
  , setUserIdSet
  , channelMentionCount
  , useNickname
  , displaynameForUserId
  , raiseInternalEvent
  , getNewMessageCutoff
  , getEditedMessageCutoff

  , normalChannelSigil

  , HighlightSet(..)
  , UserSet
  , ChannelSet
  , getHighlightSet

  , module Types.Channels
  , module Types.Messages
  , module Types.Posts
  , module Types.Users
  )
where

import           Prelude ()
import           Prelude.MH

import qualified Brick
import           Brick ( EventM, Next )
import           Brick.AttrMap ( AttrMap )
import           Brick.BChan
import           Brick.Widgets.Edit ( Editor, editor, editorText, editContentsL, applyEdit, editorName )
import           Brick.Widgets.List ( List, list )
import           Control.Concurrent.Async ( Async )
import           Control.Concurrent.MVar ( MVar )
import qualified Control.Concurrent.STM as STM
import           Control.DeepSeq
import           Control.Exception ( SomeException )
import qualified Control.Monad.State as St
import qualified Control.Monad.Reader as R
import qualified Data.Aeson as A
import qualified Data.Foldable as F
import qualified Data.HashMap.Strict as HM
import           Data.List ( partition, sortBy )
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import qualified Data.Text as T
import           Data.Text.Zipper ( textZipper, getText, getLineLimit, moveCursor, cursorPosition )
import           Data.Time.Clock ( UTCTime, getCurrentTime )
import           Data.UUID ( UUID )
import qualified Data.Vector as Vec
import           GHC.Generics ( Generic )
import           Graphics.Vty ( Attr, DisplayRegion )
import           Lens.Micro.Platform ( at, makeLenses, lens, (%~), (^?!), (.=)
                                     , (%=), (^?), (.~)
                                     , _Just, Traversal', preuse, (^..), folded, to, view )
import           Network.Connection ( HostNotResolved, HostCannotConnect )
import           Skylighting.Types ( SyntaxMap )
import           System.Exit ( ExitCode )
import           System.Random ( randomIO )
import           Text.Aspell ( Aspell )

import           Network.Mattermost ( ConnectionData )
import           Network.Mattermost.Exceptions
import           Network.Mattermost.Lenses
import           Network.Mattermost.Types
import           Network.Mattermost.Types.Config
import           Network.Mattermost.WebSocket ( WebsocketEvent )

import           Completion ( Completer )
import           InputHistory
import           Types.Channels
import           Types.Common
import           Types.DirectionalSeq ( emptyDirSeq )
import           Types.KeyEvents
import           Types.Messages
import           Types.Posts
import           Types.Users
import           Zipper ( Zipper, focusL, updateList )


-- * Configuration

-- | A user password is either given to us directly, or a command
-- which we execute to find the password.
data PasswordSource =
    PasswordString Text
    | PasswordCommand Text
    deriving (Eq, Read, Show)

instance A.ToJSON PasswordSource where
    toJSON (PasswordString _) = A.object ["type" A..= ("string"::String)]
    toJSON (PasswordCommand cmd) = A.object ["type" A..= ("command"::String), "value" A..= cmd]

instance A.FromJSON PasswordSource where
    parseJSON = A.withObject "PasswordSource" $ \o -> do
        ty :: String
           <- o A..: "type"
        case ty of
            "string" -> return $ PasswordString "<<<protected>>>"
            "command" -> PasswordCommand <$> o A..: "value"
            _ -> fail "Invalid PasswordSource"

-- | This is how we represent the user's configuration. Most fields
-- correspond to configuration file settings (see Config.hs) but some
-- are for internal book-keeping purposes only.
data Config =
    Config { configUser :: Maybe Text
           -- ^ The username to use when connecting.
           , configHost :: Maybe Text
           -- ^ The hostname to use when connecting.
           , configTeam :: Maybe Text
           -- ^ The team name to use when connecting.
           , configPort :: Int
           -- ^ The port to use when connecting.
           , configPass :: Maybe PasswordSource
           -- ^ The password source to use when connecting.
           , configTimeFormat :: Maybe Text
           -- ^ The format string for timestamps.
           , configDateFormat :: Maybe Text
           -- ^ The format string for dates.
           , configTheme :: Maybe Text
           -- ^ The name of the theme to use.
           , configThemeCustomizationFile :: Maybe Text
           -- ^ The path to the theme customization file, if any.
           , configSmartBacktick :: Bool
           -- ^ Whether to enable smart quoting characters.
           , configURLOpenCommand :: Maybe Text
           -- ^ The command to use to open URLs.
           , configURLOpenCommandInteractive :: Bool
           -- ^ Whether the URL-opening command is interactive (i.e.
           -- whether it should be given control of the terminal).
           , configActivityNotifyCommand :: Maybe T.Text
           -- ^ The command to run for activity notifications.
           , configActivityBell :: Bool
           -- ^ Whether to ring the terminal bell on activity.
           , configShowBackground :: BackgroundInfo
           -- ^ Whether to show async background worker thread info.
           , configShowMessagePreview :: Bool
           -- ^ Whether to show the message preview area.
           , configEnableAspell :: Bool
           -- ^ Whether to enable Aspell spell checking.
           , configAspellDictionary :: Maybe Text
           -- ^ A specific Aspell dictionary name to use.
           , configUnsafeUseHTTP :: Bool
           -- ^ Whether to permit an insecure HTTP connection.
           , configChannelListWidth :: Int
           -- ^ The width, in columns, of the channel list sidebar.
           , configLogMaxBufferSize :: Int
           -- ^ The maximum size, in log entries, of the internal log
           -- message buffer.
           , configShowOlderEdits :: Bool
           -- ^ Whether to highlight the edit indicator on edits made
           -- prior to the beginning of the current session.
           , configShowTypingIndicator :: Bool
           -- ^ Whether to show the typing indicator for other users,
           -- and whether to send typing notifications to other users.
           , configAbsPath :: Maybe FilePath
           -- ^ A book-keeping field for the absolute path to the
           -- configuration. (Not a user setting.)
           , configUserKeys :: KeyConfig
           -- ^ The user's keybinding configuration.
           , configHyperlinkingMode :: Bool
           -- ^ Whether to enable terminal hyperlinking mode.
           , configSyntaxDirs :: [FilePath]
           -- ^ The search path for syntax description XML files.
           } deriving (Eq, Show, Generic, A.FromJSON, A.ToJSON)

-- | The state of the UI diagnostic indicator for the async worker
-- thread.
data BackgroundInfo =
    Disabled
    -- ^ Disable (do not show) the indicator.
    | Active
    -- ^ Show the indicator when the thread is working.
    | ActiveCount
    -- ^ Show the indicator when the thread is working, but include the
    -- thread's work queue length.
    deriving (Eq, Show, Generic, A.FromJSON, A.ToJSON)

-- * 'MMNames' structures

-- | The 'MMNames' record is for listing human-readable names and
-- mapping them back to internal IDs.
data MMNames =
    MMNames { _cnChans :: [Text] -- ^ All channel names
            , _channelNameToChanId :: HashMap Text ChannelId
            -- ^ Mapping from channel names to 'ChannelId' values
            , _usernameToChanId :: HashMap Text ChannelId
            -- ^ Mapping from user names to 'ChannelId' values. Only
            -- contains entries for which DM channel IDs are known.
            , _cnUsers :: [Text] -- ^ All users
            , _cnToUserId :: HashMap Text UserId
            -- ^ Mapping from user names to 'UserId' values
            }
            deriving (Generic, A.FromJSON, A.ToJSON)

-- | MMNames constructor, seeded with an initial mapping of user ID to
-- user and channel metadata.
mkNames :: User -> HashMap UserId User -> Seq Channel -> MMNames
mkNames myUser users chans =
    MMNames { _cnChans = sort
                         [ preferredChannelName c
                         | c <- toList chans, channelType c /= Direct ]
            , _channelNameToChanId = HM.fromList [ (preferredChannelName c, channelId c) | c <- toList chans ]
            , _usernameToChanId = HM.fromList $
                            [ (userUsername u, c)
                            | u <- HM.elems users
                            , c <- lookupChan (getDMChannelName (getId myUser) (getId u))
                            ]
            , _cnUsers = sort (map userUsername (HM.elems users))
            , _cnToUserId = HM.fromList
                            [ (userUsername u, getId u) | u <- HM.elems users ]
            }
  where lookupChan n = [ c^.channelIdL
                       | c <- toList chans, (sanitizeUserText $ c^.channelNameL) == n
                       ]

-- ** 'MMNames' Lenses

makeLenses ''MMNames

-- ** 'MMNames' functions

mkChannelZipperList :: MMNames -> [ChannelId]
mkChannelZipperList chanNames =
    getChannelIdsInOrder chanNames ++
    getDMChannelIdsInOrder chanNames

getChannelIdsInOrder :: MMNames -> [ChannelId]
getChannelIdsInOrder n = [ (n ^. channelNameToChanId) HM.! i | i <- n ^. cnChans ]

getDMChannelIdsInOrder :: MMNames -> [ChannelId]
getDMChannelIdsInOrder n =
    [ c | i <- n ^. cnUsers
    , c <- maybeToList (HM.lookup i (n ^. usernameToChanId))
    ]

-- * Internal Names and References

-- | This 'Name' type is the type used in 'brick' to identify various
-- parts of the interface.
data Name =
    ChannelMessages ChannelId
    | MessageInput
    | ChannelList
    | HelpViewport
    | HelpText
    | ScriptHelpText
    | ThemeHelpText
    | SyntaxHighlightHelpText
    | KeybindingHelpText
    | ChannelSelectString
    | CompletionAlternatives
    | JoinChannelList
    | UrlList
    | MessagePreviewViewport
    | UserListSearchInput
    | UserListSearchResults
    | ViewMessageArea
    deriving (Eq, Show, Read, Ord, Generic, A.FromJSON, A.ToJSON, NFData)

-- | The sum type of exceptions we expect to encounter on authentication
-- failure. We encode them explicitly here so that we can print them in
-- a more user-friendly manner than just 'show'.
data AuthenticationException =
    ConnectError HostCannotConnect
    | ResolveError HostNotResolved
    | AuthIOError IOError
    | LoginError LoginFailureException
    | OtherAuthError SomeException
    deriving (Show)

-- | Our 'ConnectionInfo' contains exactly as much information as is
-- necessary to start a connection with a Mattermost server. This is
-- built up during interactive authentication and then is used to log
-- in.
data ConnectionInfo =
    ConnectionInfo { _ciHostname :: Text
                   , _ciPort     :: Int
                   , _ciUsername :: Text
                   , _ciPassword :: Text
                   }

makeLenses ''ConnectionInfo

-- | We want to continue referring to posts by their IDs, but we don't
-- want to have to synthesize new valid IDs for messages from the client
-- itself (like error messages or informative client responses). To that
-- end, a PostRef can be either a PostId or a newly-generated client ID.
data PostRef
    = MMId PostId
    | CLId Int
    deriving (Eq, Show, Generic, A.ToJSON, A.FromJSON)

-- Sigils
normalChannelSigil :: Text
normalChannelSigil = "~"

-- ** Channel-matching types

-- | A match in channel selection mode.
data ChannelSelectMatch =
    ChannelSelectMatch { nameBefore     :: Text
                       -- ^ The content of the match before the user's
                       -- matching input.
                       , nameMatched    :: Text
                       -- ^ The potion of the name that matched the
                       -- user's input.
                       , nameAfter      :: Text
                       -- ^ The portion of the name that came after the
                       -- user's matching input.
                       , matchFull      :: Text
                       -- ^ The full string for this entry so it doesn't
                       -- have to be reassembled from the parts above.
                       }
                       deriving (Eq, Show, Generic, A.ToJSON, A.FromJSON)

data ChannelSelectPattern = CSP MatchType Text
                          deriving (Eq, Show)

data MatchType =
    Prefix
    | Suffix
    | Infix
    | Equal
    | UsersOnly
    | ChannelsOnly
    deriving (Eq, Show)

-- * Application State Values

data ProgramOutput =
    ProgramOutput { program :: FilePath
                  , programArgs :: [String]
                  , programStdout :: String
                  , programStdoutExpected :: Bool
                  , programStderr :: String
                  , programExitCode :: ExitCode
                  }

data UserPreferences =
    UserPreferences { _userPrefShowJoinLeave     :: Bool
                    , _userPrefFlaggedPostList   :: Seq FlaggedPost
                    , _userPrefGroupChannelPrefs :: HashMap ChannelId Bool
                    }
                    deriving (Generic, A.FromJSON, A.ToJSON)

defaultUserPreferences :: UserPreferences
defaultUserPreferences =
    UserPreferences { _userPrefShowJoinLeave     = True
                    , _userPrefFlaggedPostList   = mempty
                    , _userPrefGroupChannelPrefs = mempty
                    }

setUserPreferences :: Seq Preference -> UserPreferences -> UserPreferences
setUserPreferences = flip (F.foldr go)
    where go p u
            | Just fp <- preferenceToFlaggedPost p =
              u { _userPrefFlaggedPostList =
                  _userPrefFlaggedPostList u Seq.|> fp
                }
            | Just gp <- preferenceToGroupChannelPreference p =
              u { _userPrefGroupChannelPrefs =
                  HM.insert
                    (groupChannelId gp)
                    (groupChannelShow gp)
                    (_userPrefGroupChannelPrefs u)
                }
            | preferenceName p == PreferenceName "join_leave" =
              u { _userPrefShowJoinLeave =
                  preferenceValue p /= PreferenceValue "false" }
            | otherwise = u

-- | Log message tags.
data LogCategory =
    LogGeneral
    | LogAPI
    | LogWebsocket
    | LogError
    deriving (Eq, Show)

-- | A log message.
data LogMessage =
    LogMessage { logMessageText :: !Text
               -- ^ The text of the log message.
               , logMessageContext :: !(Maybe LogContext)
               -- ^ The optional context information relevant to the log
               -- message.
               , logMessageCategory :: !LogCategory
               -- ^ The category of the log message.
               , logMessageTimestamp :: !UTCTime
               -- ^ The timestamp of the log message.
               }
               deriving (Show)

-- | A logging thread command.
data LogCommand =
    LogToFile FilePath
    -- ^ Start logging to the specified path.
    | LogAMessage !LogMessage
    -- ^ Log the specified message.
    | StopLogging
    -- ^ Stop any active logging.
    | ShutdownLogging
    -- ^ Shut down.
    | GetLogDestination
    -- ^ Ask the logging thread about its active logging destination.
    | LogSnapshot FilePath
    -- ^ Ask the logging thread to dump the current buffer to the
    -- specified destination.
    deriving (Show)

-- | A handle to the log manager thread.
data LogManager =
    LogManager { logManagerCommandChannel :: STM.TChan LogCommand
               , logManagerHandle :: Async ()
               }

startLoggingToFile :: LogManager -> FilePath -> IO ()
startLoggingToFile mgr loc = sendLogCommand mgr $ LogToFile loc

stopLoggingToFile :: LogManager -> IO ()
stopLoggingToFile mgr = sendLogCommand mgr StopLogging

requestLogSnapshot :: LogManager -> FilePath -> IO ()
requestLogSnapshot mgr path = sendLogCommand mgr $ LogSnapshot path

requestLogDestination :: LogManager -> IO ()
requestLogDestination mgr = sendLogCommand mgr GetLogDestination

sendLogMessage :: LogManager -> LogMessage -> IO ()
sendLogMessage mgr lm = sendLogCommand mgr $ LogAMessage lm

sendLogCommand :: LogManager -> LogCommand -> IO ()
sendLogCommand mgr c =
    STM.atomically $ STM.writeTChan (logManagerCommandChannel mgr) c

deriving instance A.ToJSON AttrMap
deriving instance A.FromJSON AttrMap

deriving instance A.ToJSON Brick.AttrName
deriving instance A.ToJSONKey Brick.AttrName
deriving instance A.FromJSON Brick.AttrName
deriving instance A.FromJSONKey Brick.AttrName

instance A.ToJSON Attr where
    toJSON = A.toJSON . show

instance A.FromJSON Attr where
    parseJSON = A.withText "Attr" $ \t -> case readMaybe (T.unpack t) of
        Nothing -> fail "Invalid Attr"
        Just a -> return a

-- | 'ChatResources' represents configuration and connection-related
-- information, as opposed to current model or view information.
-- Information that goes in the 'ChatResources' value should be limited
-- to information that we read or set up prior to setting up the bulk of
-- the application state.
data ChatResources =
    ChatResources { _crTheme               :: AttrMap
                  , _crConfiguration       :: Config
                  , _crFlaggedPosts        :: Set PostId
                  , _crUserPreferences     :: UserPreferences
                  , _crSyntaxMap           :: SyntaxMap
                  , _crMutable             :: MutableResources
                  }

instance A.ToJSON ChatResources where
    toJSON (ChatResources {..}) =
        A.object [ "theme" A..= _crTheme
                 , "config" A..= _crConfiguration
                 , "flaggedPosts" A..= _crFlaggedPosts
                 , "prefs" A..= _crUserPreferences
                 , "syntaxMap" A..= show _crSyntaxMap
                 ]

instance A.FromJSON ChatResources where
    parseJSON = A.withObject "ChatResources" $ \o -> do
        sMapTxt <- o A..: "syntaxMap"
        case readMaybe sMapTxt of
            Nothing -> fail "Invalid ChatResources"
            Just m ->
                ChatResources <$> o A..: "theme"
                              <*> o A..: "config"
                              <*> o A..: "flaggedPosts"
                              <*> o A..: "prefs"
                              <*> pure m
                              <*> pure EmptyMutableResources

-- | Mutable or volatile chat resources. We keep these in their own type
-- so we can serialize chat states without attempting to serialize
-- these values. In that case we fill in this value with
-- EmptyMutableResources; otherwise, under normal operating conditions,
-- this value is always a MutableResources. Because we have this
-- structure, we don't generate lenses for this type because makeLenses
-- will generate Traversals for all of the record fields to account for
-- the fact that not all MutableResources values will be usable with the
-- record field lenses otherwise. That creates enough of an API headache
-- (and isn't even necessary in practice because these fields rarely
-- actually *need* to be changed) that we don't bother with lenses at
-- all for this type.
data MutableResources =
    EmptyMutableResources
    | MutableResources { mutSession             :: Session
                       , mutConn                :: ConnectionData
                       , mutRequestQueue        :: RequestChan
                       , mutEventQueue          :: BChan MHEvent
                       , mutSubprocessLog       :: STM.TChan ProgramOutput
                       , mutWebsocketActionChan :: STM.TChan WebsocketAction
                       , mutUserStatusLock      :: MVar ()
                       , mutUserIdSet           :: STM.TVar (Seq UserId)
                       , mutLogManager          :: LogManager
                       , mutSpellChecker        :: Maybe (Aspell, IO ())
                       }

instance A.FromJSON MutableResources where
    parseJSON = A.withObject "MutableResources" $ const $ return EmptyMutableResources

instance A.ToJSON MutableResources where
    toJSON = const $ A.object []

-- | The 'ChatEditState' value contains the editor widget itself as well
-- as history and metadata we need for editing-related operations.
data ChatEditState =
    ChatEditState { _cedEditor               :: Editor Text Name
                  , _cedEditMode             :: EditMode
                  , _cedMultiline            :: Bool
                  , _cedInputHistory         :: InputHistory
                  , _cedInputHistoryPosition :: HashMap ChannelId (Maybe Int)
                  , _cedLastChannelInput     :: HashMap ChannelId (Text, EditMode)
                  , _cedCompleter            :: Maybe Completer
                  , _cedYankBuffer           :: Text
                  , _cedMisspellings         :: Set Text
                  }
                  deriving (Generic, A.FromJSON, A.ToJSON)

-- | The input mode.
data EditMode =
    NewPost
    -- ^ The input is for a new post.
    | Editing Post MessageType
    -- ^ The input is to be used as a new body for an existing post of
    -- the specified type.
    | Replying Message Post
    -- ^ The input is to be used as a new post in reply to the specified
    -- post.
    deriving (Show, Generic, A.FromJSON, A.ToJSON)

-- | We can initialize a new 'ChatEditState' value with just an edit
-- history, which we save locally.
emptyEditState :: InputHistory -> ChatEditState
emptyEditState hist =
    ChatEditState { _cedEditor               = editor MessageInput Nothing ""
                  , _cedMultiline            = False
                  , _cedInputHistory         = hist
                  , _cedInputHistoryPosition = mempty
                  , _cedLastChannelInput     = mempty
                  , _cedCompleter            = Nothing
                  , _cedEditMode             = NewPost
                  , _cedYankBuffer           = ""
                  , _cedMisspellings         = mempty
                  }

-- | A 'RequestChan' is a queue of operations we have to perform in the
-- background to avoid blocking on the main loop
type RequestChan = STM.TChan (IO (MH ()))

-- | The 'HelpScreen' type represents the set of possible 'Help'
-- dialogues we have to choose from.
data HelpScreen =
    MainHelp
    | ScriptHelp
    | ThemeHelp
    | SyntaxHighlightHelp
    | KeybindingHelp
    deriving (Eq, Generic, A.FromJSON, A.ToJSON)

-- | Help topics
data HelpTopic =
    HelpTopic { helpTopicName         :: Text
              , helpTopicDescription  :: Text
              , helpTopicScreen       :: HelpScreen
              , helpTopicViewportName :: Name
              }
              deriving (Eq, Generic, A.FromJSON, A.ToJSON)

-- | Mode type for the current contents of the post list overlay
data PostListContents =
    PostListFlagged
    | PostListSearch Text Bool -- for the query and search status
    deriving (Eq, Generic, A.FromJSON, A.ToJSON)

-- | The 'Mode' represents the current dominant UI activity
data Mode =
    Main
    | ShowHelp HelpTopic
    | ChannelSelect
    | UrlSelect
    | LeaveChannelConfirm
    | DeleteChannelConfirm
    | JoinChannel
    | ChannelScroll
    | MessageSelect
    | MessageSelectDeleteConfirm
    | PostListOverlay PostListContents
    | UserListOverlay
    | ViewMessage
    deriving (Eq, Generic, A.FromJSON, A.ToJSON)

-- | We're either connected or we're not.
data ConnectionStatus = Connected | Disconnected
                      deriving (Generic, A.FromJSON, A.ToJSON)

instance A.ToJSON (Editor T.Text Name) where
    toJSON e =
        let z = e^.editContentsL
        in A.object [ "contents" A..= getText z
                    , "cursor" A..= cursorPosition z
                    , "name" A..= editorName e
                    , "limit" A..= getLineLimit z
                    ]

instance (A.FromJSON n) => A.FromJSON (Editor T.Text n) where
    parseJSON = A.withObject "Editor" $ \o -> do
        contents <- o A..: "contents"
        cursor <- o A..: "cursor"
        name <- o A..: "name"
        limit <- o A..: "limit"
        let updateZipper = const $ moveCursor cursor $ textZipper contents limit
        return $ applyEdit updateZipper (editorText name limit "")

deriving instance (A.ToJSON n, A.ToJSON e) => A.ToJSON (List n e)
deriving instance (A.FromJSON n, A.FromJSON e) => A.FromJSON (List n e)

instance A.FromJSON TimeZoneSeries where
    parseJSON = A.withText "TimeZoneSeries" $ \t ->
        case readMaybe (T.unpack t) of
            Nothing -> fail "Invalid TimeZoneSeries"
            Just val -> return val

instance A.ToJSON TimeZoneSeries where
    toJSON = A.toJSON . show

-- | This is the giant bundle of fields that represents the current
-- state of our application at any given time.
data ChatState =
    ChatState { _csResources :: ChatResources
              -- ^ Global application-wide resources that don't change
              -- much.
              , _csFocus :: Zipper ChannelId
              -- ^ The channel sidebar zipper that tracks which channel
              -- is selected.
              , _csNames :: MMNames
              -- ^ Mappings between names and user/channel IDs.
              , _csMe :: User
              -- ^ The authenticated user.
              , _csMyTeam :: Team
              -- ^ The active team of the authenticated user.
              , _csChannels :: ClientChannels
              -- ^ The channels that we are showing, including their
              -- message lists.
              , _csPostMap :: HashMap PostId Message
              -- ^ The map of post IDs to messages. This allows us to
              -- access messages by ID without having to linearly scan
              -- channel message lists.
              , _csUsers :: Users
              -- ^ All of the users we know about.
              , _timeZone :: TimeZoneSeries
              -- ^ The client time zone.
              , _csEditState :: ChatEditState
              -- ^ The state of the input box used for composing and
              -- editing messages and commands.
              , _csMode :: Mode
              -- ^ The current application mode. This is used to
              -- dispatch to different rendering and event handling
              -- routines.
              , _csShowMessagePreview :: Bool
              -- ^ Whether to show the message preview area.
              , _csChannelSelectState :: ChannelSelectState
              -- ^ The state of the user's input and selection for
              -- channel selection mode.
              , _csRecentChannel :: Maybe ChannelId
              -- ^ The most recently-selected channel, if any.
              , _csUrlList :: List Name LinkChoice
              -- ^ The URL list used to show URLs drawn from messages in
              -- a channel.
              , _csConnectionStatus :: ConnectionStatus
              -- ^ Our view of the connection status.
              , _csWorkerIsBusy :: Maybe (Maybe Int)
              -- ^ Whether the async worker thread is busy, and its
              -- queue length if so.
              , _csJoinChannelList :: Maybe (List Name Channel)
              -- ^ The list of channels presented in the channel join
              -- window.
              , _csMessageSelect :: MessageSelectState
              -- ^ The state of message selection mode.
              , _csPostListOverlay :: PostListOverlayState
              -- ^ The state of the post list overlay.
              , _csUserListOverlay :: UserListOverlayState
              -- ^ The state of the user list overlay.
              , _csClientConfig :: Maybe ClientConfig
              -- ^ The Mattermost client configuration, as we understand it.
              , _csLastJoinRequest :: Maybe ChannelId
              -- ^ The most recently-joined channel ID that we look for
              -- in an asynchronous join notification, so that we can
              -- switch to it in the sidebar.
              , _csViewedMessage :: Maybe Message
              -- ^ Set when the ViewMessage mode is active. The message
              -- being viewed.
              }
              deriving (Generic, A.FromJSON, A.ToJSON)

-- | Startup state information that is constructed prior to building a
-- ChatState.
data StartupStateInfo =
    StartupStateInfo { startupStateResources      :: ChatResources
                     , startupStateChannelZipper  :: Zipper ChannelId
                     , startupStateConnectedUser  :: User
                     , startupStateTeam           :: Team
                     , startupStateTimeZone       :: TimeZoneSeries
                     , startupStateInitialHistory :: InputHistory
                     , startupStateNames          :: MMNames
                     }

newState :: StartupStateInfo -> ChatState
newState (StartupStateInfo {..}) =
    ChatState { _csResources                   = startupStateResources
              , _csFocus                       = startupStateChannelZipper
              , _csMe                          = startupStateConnectedUser
              , _csMyTeam                      = startupStateTeam
              , _csNames                       = startupStateNames
              , _csChannels                    = noChannels
              , _csPostMap                     = HM.empty
              , _csUsers                       = noUsers
              , _timeZone                      = startupStateTimeZone
              , _csEditState                   = emptyEditState startupStateInitialHistory
              , _csMode                        = Main
              , _csShowMessagePreview          = configShowMessagePreview $ _crConfiguration startupStateResources
              , _csChannelSelectState          = emptyChannelSelectState
              , _csRecentChannel               = Nothing
              , _csUrlList                     = list UrlList mempty 2
              , _csConnectionStatus            = Connected
              , _csWorkerIsBusy                = Nothing
              , _csJoinChannelList             = Nothing
              , _csMessageSelect               = MessageSelectState Nothing
              , _csPostListOverlay             = PostListOverlayState emptyDirSeq Nothing
              , _csUserListOverlay             = nullUserListOverlayState
              , _csClientConfig                = Nothing
              , _csLastJoinRequest             = Nothing
              , _csViewedMessage               = Nothing
              }

nullUserListOverlayState :: UserListOverlayState
nullUserListOverlayState =
    UserListOverlayState { _userListSearchResults  = listFromUserSearchResults mempty
                         , _userListSearchInput    = editor UserListSearchInput (Just 1) ""
                         , _userListSearchScope    = AllUsers
                         , _userListSearching      = False
                         , _userListRequestingMore = False
                         , _userListHasAllResults  = False
                         , _userListActivateType   = DoNothing
                         }

listFromUserSearchResults :: Vec.Vector UserInfo -> List Name UserInfo
listFromUserSearchResults rs =
    -- NB: The item height here needs to actually match the UI drawing
    -- in Draw.UserListOverlay.
    list UserListSearchResults rs 1

-- | A match in channel selection mode. Constructors distinguish
-- between channel and user matches to ensure that a match of each type
-- is distinct.
data MatchValue =
    UserMatch Text
    | ChannelMatch Text
    deriving (Eq, Show, Generic, A.FromJSON, A.ToJSON)

-- | The state of channel selection mode.
data ChannelSelectState =
    ChannelSelectState { _channelSelectInput :: Text
                       , _channelMatches     :: [ChannelSelectMatch]
                       , _userMatches        :: [ChannelSelectMatch]
                       , _selectedMatch      :: Maybe MatchValue
                       }
                       deriving (Generic, A.FromJSON, A.ToJSON)

emptyChannelSelectState :: ChannelSelectState
emptyChannelSelectState =
    ChannelSelectState { _channelSelectInput = ""
                       , _channelMatches     = mempty
                       , _userMatches        = mempty
                       , _selectedMatch      = Nothing
                       }

-- | The state of message selection mode.
data MessageSelectState =
    MessageSelectState { selectMessageId :: Maybe MessageId
                       }
                       deriving (Generic, A.FromJSON, A.ToJSON)

-- | The state of the post list overlay.
data PostListOverlayState =
    PostListOverlayState { _postListPosts    :: Messages
                         , _postListSelected :: Maybe PostId
                         }
                         deriving (Generic, A.FromJSON, A.ToJSON)

data UserListActivateType =
    DoNothing
    | ChangeToChannel
    | AddToCurrentChannel
    deriving (Show, Generic, A.FromJSON, A.ToJSON)

-- | The state of the user list overlay.
data UserListOverlayState =
    UserListOverlayState { _userListSearchResults :: List Name UserInfo
                         , _userListSearchInput :: Editor Text Name
                         , _userListSearchScope :: UserSearchScope
                         , _userListSearching :: Bool
                         , _userListRequestingMore :: Bool
                         , _userListHasAllResults :: Bool
                         , _userListActivateType :: UserListActivateType
                         }
                         deriving (Generic, A.FromJSON, A.ToJSON)

-- | The scope for searching for users in a user list overlay.
data UserSearchScope =
    ChannelMembers ChannelId
    | ChannelNonMembers ChannelId
    | AllUsers
    deriving (Generic, A.FromJSON, A.ToJSON)

-- | Actions that can be sent on the websocket to the server.
data WebsocketAction =
    UserTyping UTCTime ChannelId (Maybe PostId) -- ^ user typing in the input box
    deriving (Read, Show, Eq, Ord)

-- * MH Monad

-- | Logging context information, in the event that metadata should
-- accompany a log message.
data LogContext =
    LogContext { logContextChannelId :: Maybe ChannelId
               }
               deriving (Eq, Show)

-- | A value of type 'MH' @a@ represents a computation that can
-- manipulate the application state and also request that the
-- application quit
newtype MH a =
    MH { fromMH :: R.ReaderT (Maybe LogContext) (St.StateT (ChatState, ChatState -> EventM Name (Next ChatState)) (EventM Name)) a }

-- | Use a modified logging context for the duration of the specified MH
-- action.
withLogContext :: (Maybe LogContext -> Maybe LogContext) -> MH a -> MH a
withLogContext modifyContext act =
    MH $ R.withReaderT modifyContext (fromMH act)

withLogContextChannelId :: ChannelId -> MH a -> MH a
withLogContextChannelId cId act =
    let f Nothing = Just $ LogContext (Just cId)
        f (Just c) = Just $ c { logContextChannelId = Just cId }
    in withLogContext f act

-- | Get the current logging context.
getLogContext :: MH (Maybe LogContext)
getLogContext = MH R.ask

-- | Log a message.
mhLog :: LogCategory -> Text -> MH ()
mhLog cat msg = do
    logger <- mhGetIOLogger
    liftIO $ logger cat msg

-- | Get a logger suitable for use in IO. The logger always logs using
-- the MH monad log context at the time of the call to mhGetIOLogger.
mhGetIOLogger :: MH (LogCategory -> Text -> IO ())
mhGetIOLogger = do
    ctx <- getLogContext
    mgr <- use (to (mutLogManager._crMutable._csResources))
    return $ \cat msg -> do
        now <- liftIO getCurrentTime
        let lm = LogMessage { logMessageText = msg
                            , logMessageContext = ctx
                            , logMessageCategory = cat
                            , logMessageTimestamp = now
                            }
        liftIO $ sendLogMessage mgr lm

-- | Run an 'MM' computation, choosing whether to continue or halt based
-- on the resulting
runMHEvent :: ChatState -> MH () -> EventM Name (Next ChatState)
runMHEvent st (MH mote) = do
  ((), (st', rs)) <- St.runStateT (R.runReaderT mote Nothing) (st, Brick.continue)
  rs st'

-- | lift a computation in 'EventM' into 'MH'
mh :: EventM Name a -> MH a
mh = MH . R.lift . St.lift

generateUUID :: MH UUID
generateUUID = liftIO generateUUID_IO

generateUUID_IO :: IO UUID
generateUUID_IO = randomIO

mhHandleEventLensed :: Lens' ChatState b -> (e -> b -> EventM Name b) -> e -> MH ()
mhHandleEventLensed ln f event = MH $ do
    (st, b) <- St.get
    n <- R.lift $ St.lift $ f event (st ^. ln)
    St.put (st & ln .~ n , b)

mhSuspendAndResume :: (ChatState -> IO ChatState) -> MH ()
mhSuspendAndResume mote = MH $ do
    (st, _) <- St.get
    St.put (st, \ _ -> Brick.suspendAndResume (mote st))

-- | This will request that after this computation finishes the
-- application should exit
requestQuit :: MH ()
requestQuit = MH $ do
    (st, _) <- St.get
    St.put (st, Brick.halt)

instance Functor MH where
    fmap f (MH x) = MH (fmap f x)

instance Applicative MH where
    pure x = MH (pure x)
    MH f <*> MH x = MH (f <*> x)

instance Monad MH where
    return x = MH (return x)
    MH x >>= f = MH (x >>= \ x' -> fromMH (f x'))

-- We want to pretend that the state is only the ChatState, rather
-- than the ChatState and the Brick continuation
instance St.MonadState ChatState MH where
    get = fst `fmap` MH St.get
    put st = MH $ do
        (_, c) <- St.get
        St.put (st, c)

instance St.MonadIO MH where
    liftIO = MH . St.liftIO

-- | This represents events that we handle in the main application loop.
data MHEvent =
    WSEvent WebsocketEvent
    -- ^ For events that arise from the websocket
    | RespEvent (MH ())
    -- ^ For the result values of async IO operations
    | RefreshWebsocketEvent
    -- ^ Tell our main loop to refresh the websocket connection
    | WebsocketParseError String
    -- ^ We failed to parse an incoming websocket event
    | WebsocketDisconnect
    -- ^ The websocket connection went down.
    | WebsocketConnect
    -- ^ The websocket connection came up.
    | BGIdle
    -- ^ background worker is idle
    | BGBusy (Maybe Int)
    -- ^ background worker is busy (with n requests)
    | IEvent InternalEvent
    -- ^ MH-internal events

-- | Internal application events.
data InternalEvent =
    DisplayError MHError
    -- ^ Some kind of application error occurred
    | LoggingStarted FilePath
    | LoggingStopped FilePath
    | LogStartFailed FilePath String
    | LogDestination (Maybe FilePath)
    | LogSnapshotSucceeded FilePath
    | LogSnapshotFailed FilePath String
    -- ^ Logging events from the logging thread

-- | Application errors.
data MHError =
    GenericError T.Text
    -- ^ A generic error message constructor
    | NoSuchChannel T.Text
    -- ^ The specified channel does not exist
    | NoSuchUser T.Text
    -- ^ The specified user does not exist
    | AmbiguousName T.Text
    -- ^ The specified name matches both a user and a channel
    | ServerError MattermostError
    -- ^ A Mattermost server error occurred
    | ClipboardError T.Text
    -- ^ A problem occurred trying to deal with yanking or the system
    -- clipboard
    | ConfigOptionMissing T.Text
    -- ^ A missing config option is required to perform an operation
    | ProgramExecutionFailed T.Text T.Text
    -- ^ Args: program name, path to log file. A problem occurred when
    -- running the program.
    | NoSuchScript T.Text
    -- ^ The specified script was not found
    | NoSuchHelpTopic T.Text
    -- ^ The specified help topic was not found
    | AsyncErrEvent SomeException
    -- ^ For errors that arise in the course of async IO operations
    deriving (Show)

-- ** Application State Lenses

makeLenses ''ChatResources
makeLenses ''ChatState
makeLenses ''ChatEditState
makeLenses ''PostListOverlayState
makeLenses ''UserListOverlayState
makeLenses ''ChannelSelectState
makeLenses ''UserPreferences

getSession :: MH Session
getSession = St.gets (mutSession._crMutable._csResources)

getResourceSession :: ChatResources -> Session
getResourceSession = mutSession._crMutable

whenMode :: Mode -> MH () -> MH ()
whenMode m act = do
    curMode <- use csMode
    when (curMode == m) act

setMode :: Mode -> MH ()
setMode = (csMode .=)

setMode' :: Mode -> ChatState -> ChatState
setMode' m st = st & csMode .~ m

appMode :: ChatState -> Mode
appMode = _csMode

resetSpellCheckTimer :: ChatState -> IO ()
resetSpellCheckTimer s =
    case s^.csResources.crMutable.to mutSpellChecker of
        Nothing -> return ()
        Just (_, reset) -> reset

-- ** Utility Lenses
csCurrentChannelId :: Lens' ChatState ChannelId
csCurrentChannelId = csFocus.focusL

csCurrentChannel :: Lens' ChatState ClientChannel
csCurrentChannel =
    lens (\ st -> findChannelById (st^.csCurrentChannelId) (st^.csChannels) ^?! _Just)
         (\ st n -> st & csChannels %~ addChannel (st^.csCurrentChannelId) n)

csChannel :: ChannelId -> Traversal' ChatState ClientChannel
csChannel cId =
    csChannels . channelByIdL cId

withChannel :: ChannelId -> (ClientChannel -> MH ()) -> MH ()
withChannel cId = withChannelOrDefault cId ()

withChannelOrDefault :: ChannelId -> a -> (ClientChannel -> MH a) -> MH a
withChannelOrDefault cId deflt mote = do
    chan <- preuse (csChannel(cId))
    case chan of
        Nothing -> return deflt
        Just c  -> mote c

-- ** 'ChatState' Helper Functions

raiseInternalEvent :: InternalEvent -> MH ()
raiseInternalEvent ev = do
    queue <- St.gets (mutEventQueue._crMutable._csResources)
    St.liftIO $ writeBChan queue (IEvent ev)

-- | Log and raise an error.
mhError :: MHError -> MH ()
mhError err = do
    mhLog LogError $ T.pack $ show err
    raiseInternalEvent (DisplayError err)

isMine :: ChatState -> Message -> Bool
isMine st msg = (UserI $ myUserId st) == msg^.mUser

getMessageForPostId :: ChatState -> PostId -> Maybe Message
getMessageForPostId st pId = st^.csPostMap.at(pId)

getParentMessage :: ChatState -> Message -> Maybe Message
getParentMessage st msg
    | InReplyTo pId <- msg^.mInReplyToMsg
      = st^.csPostMap.at(pId)
    | otherwise = Nothing

setUserStatus :: UserId -> Text -> MH ()
setUserStatus uId t = csUsers %= modifyUserById uId (uiStatus .~ statusFromText t)

nicknameForUserId :: UserId -> ChatState -> Maybe Text
nicknameForUserId uId st = _uiNickName =<< findUserById uId (st^.csUsers)

usernameForUserId :: UserId -> ChatState -> Maybe Text
usernameForUserId uId st = _uiName <$> findUserById uId (st^.csUsers)

displaynameForUserId :: UserId -> ChatState -> Maybe Text
displaynameForUserId uId st
    | useNickname st =
        nicknameForUserId uId st <|> usernameForUserId uId st
    | otherwise =
        usernameForUserId uId st


userIdForUsername :: Text -> ChatState -> Maybe UserId
userIdForUsername name st = st^.csNames.cnToUserId.at (trimUserSigil name)

channelIdByChannelName :: Text -> ChatState -> Maybe ChannelId
channelIdByChannelName name st =
    HM.lookup (trimChannelSigil name) $ st^.csNames.channelNameToChanId

-- | Get a channel ID by username or channel name. Returns (channel
-- match, user match). Note that this returns multiple results because
-- it's possible for there to be a match for both users and channels.
-- Note that this function uses sigils on the input to guarantee clash
-- avoidance, i.e., that if the user sigil is present in the input,
-- only users will be searched. This allows callers (or the user) to
-- disambiguate by sigil, which may be necessary in cases where an input
-- with no sigil finds multiple matches.
channelIdByName :: Text -> ChatState -> (Maybe ChannelId, Maybe ChannelId)
channelIdByName name st =
    let uMatch = channelIdByUsername name st
        cMatch = channelIdByChannelName name st
        matches =
            if | userSigil `T.isPrefixOf` name          -> (Nothing, uMatch)
               | normalChannelSigil `T.isPrefixOf` name -> (cMatch, Nothing)
               | otherwise                              -> (cMatch, uMatch)
    in matches

channelIdByUsername :: Text -> ChatState -> Maybe ChannelId
channelIdByUsername name st =
    let userInfos = st^.csUsers.to allUsers
        uName = if useNickname st
                then
                    maybe name (view uiName)
                              $ findUserByNickname userInfos name
                else name
        nameToChanId = st^.csNames.usernameToChanId
    in HM.lookup (trimUserSigil uName) nameToChanId

useNickname :: ChatState -> Bool
useNickname st = case st^?csClientConfig._Just.to clientConfigTeammateNameDisplay of
                      Just "nickname_full_name" ->
                          True
                      _ ->
                          False

channelByName :: Text -> ChatState -> Maybe ClientChannel
channelByName n st = do
    cId <- channelIdByChannelName n st
    findChannelById cId (st^.csChannels)

trimChannelSigil :: Text -> Text
trimChannelSigil n
    | normalChannelSigil `T.isPrefixOf` n = T.tail n
    | otherwise                           = n

addNewUser :: UserInfo -> MH ()
addNewUser u = do
    csUsers %= addUser u

    let uname = u^.uiName
        uid = u^.uiId
    csNames.cnUsers %= (sort . (uname:))
    csNames.cnToUserId.at uname .= Just uid

    userSet <- St.gets (mutUserIdSet._crMutable._csResources)
    St.liftIO $ STM.atomically $ STM.modifyTVar userSet $ (uid Seq.<|)

setUserIdSet :: Seq UserId -> MH ()
setUserIdSet ids = do
    userSet <- St.gets (mutUserIdSet._crMutable._csResources)
    St.liftIO $ STM.atomically $ STM.writeTVar userSet ids

addChannelName :: Type -> ChannelId -> Text -> MH ()
addChannelName chType cid name = do
    case chType of
        Direct -> csNames.usernameToChanId.at(name) .= Just cid
        _ -> csNames.channelNameToChanId.at(name) .= Just cid

    -- For direct channels the username is already in the user list so
    -- do nothing
    existingNames <- St.gets allChannelNames
    when (chType /= Direct && (not $ name `elem` existingNames)) $
        csNames.cnChans %= (sort . (name:))

channelMentionCount :: ChannelId -> ChatState -> Int
channelMentionCount cId st =
    maybe 0 id (st^?csChannel(cId).ccInfo.cdMentionCount)

allChannelNames :: ChatState -> [Text]
allChannelNames st = st^.csNames.cnChans

allUsernames :: ChatState -> [Text]
allUsernames st = st^.csNames.cnChans

removeChannelName :: Text -> MH ()
removeChannelName name = do
    -- Flush cnToChanId
    csNames.channelNameToChanId.at name .= Nothing
    -- Flush cnChans
    csNames.cnChans %= filter (/= name)

-- Rebuild the channel zipper contents from the current names collection.
refreshChannelZipper :: MH ()
refreshChannelZipper = do
    -- We should figure out how to do this better: this adds it to the
    -- channel zipper in such a way that we don't ever change our focus
    -- to something else, which is kind of silly
    names <- use csNames
    let newZip = updateList (mkChannelZipperList names)
    csFocus %= newZip

clientPostToMessage :: ClientPost -> Message
clientPostToMessage cp =
    Message { _mText = cp^.cpText
            , _mMarkdownSource = cp^.cpMarkdownSource
            , _mUser =
                case cp^.cpUserOverride of
                    Just n | cp^.cpType == NormalPost -> UserOverride (n <> "[BOT]")
                    _ -> maybe NoUser UserI $ cp^.cpUser
            , _mDate = cp^.cpDate
            , _mType = CP $ cp^.cpType
            , _mPending = cp^.cpPending
            , _mDeleted = cp^.cpDeleted
            , _mAttachments = cp^.cpAttachments
            , _mInReplyToMsg =
                case cp^.cpInReplyToPost of
                    Nothing  -> NotAReply
                    Just pId -> InReplyTo pId
            , _mMessageId = Just $ MessagePostId $ cp^.cpPostId
            , _mReactions = cp^.cpReactions
            , _mOriginalPost = Just $ cp^.cpOriginalPost
            , _mFlagged = False
            , _mChannelId = Just $ cp^.cpChannelId
            }

-- * Slash Commands

-- | The 'CmdArgs' type represents the arguments to a slash-command; the
-- type parameter represents the argument structure.
data CmdArgs :: * -> * where
    NoArg    :: CmdArgs ()
    LineArg  :: Text -> CmdArgs Text
    TokenArg :: Text -> CmdArgs rest -> CmdArgs (Text, rest)

-- | A 'CmdExec' value represents the implementation of a command when
-- provided with its arguments
type CmdExec a = a -> MH ()

-- | A 'Cmd' packages up a 'CmdArgs' specifier and the 'CmdExec'
-- implementation with a name and a description.
data Cmd =
    forall a. Cmd { cmdName    :: Text
                  , cmdDescr   :: Text
                  , cmdArgSpec :: CmdArgs a
                  , cmdAction  :: CmdExec a
                  }

-- | Helper function to extract the name out of a 'Cmd' value
commandName :: Cmd -> Text
commandName (Cmd name _ _ _ ) = name

-- *  Channel Updates and Notifications

hasUnread :: ChatState -> ChannelId -> Bool
hasUnread st cId = maybe False id $ do
    chan <- findChannelById cId (st^.csChannels)
    lastViewTime <- chan^.ccInfo.cdViewed
    return $ (chan^.ccInfo.cdUpdated > lastViewTime) ||
             (isJust $ chan^.ccInfo.cdEditedMessageThreshold)

userList :: ChatState -> [UserInfo]
userList st = filter showUser $ allUsers (st^.csUsers)
    where showUser u = not (isSelf u) && (u^.uiInTeam)
          isSelf u = (myUserId st) == (u^.uiId)

allUserIds :: ChatState -> [UserId]
allUserIds st = getAllUserIds $ st^.csUsers

userById :: UserId -> ChatState -> Maybe UserInfo
userById uId st = findUserById uId (st^.csUsers)

myUserId :: ChatState -> UserId
myUserId st = myUser st ^. userIdL

myTeamId :: ChatState -> TeamId
myTeamId st = st ^. csMyTeam . teamIdL

myUser :: ChatState -> User
myUser st = st^.csMe

userByDMChannelName :: Text
                    -- ^ the dm channel name
                    -> UserId
                    -- ^ me
                    -> ChatState
                    -> Maybe UserInfo
                    -- ^ you
userByDMChannelName name self st =
    findUserByDMChannelName (st^.csUsers) name self

userByUsername :: Text -> ChatState -> Maybe UserInfo
userByUsername name st = do
    uId <- userIdForUsername name st
    userById uId st

sortedUserList :: ChatState -> [UserInfo]
sortedUserList st = sortBy cmp yes <> sortBy cmp no
    where
        cmp = compareUserInfo uiName
        dmHasUnread u =
            case st^.csNames.usernameToChanId.at(u^.uiName) of
              Nothing  -> False
              Just cId
                | (st^.csCurrentChannelId) == cId -> False
                | otherwise -> hasUnread st cId
        (yes, no) = partition dmHasUnread (filter (not . _uiDeleted) $ userList st)

compareUserInfo :: (Ord a) => Lens' UserInfo a -> UserInfo -> UserInfo -> Ordering
compareUserInfo field u1 u2
    | u1^.uiStatus == Offline && u2^.uiStatus /= Offline =
      GT
    | u1^.uiStatus /= Offline && u2^.uiStatus == Offline =
      LT
    | otherwise =
      (u1^.field) `compare` (u2^.field)

-- * HighlightSet

type UserSet = Set Text
type ChannelSet = Set Text

-- | The set of usernames, channel names, and language names used for
-- highlighting when rendering messages.
data HighlightSet =
    HighlightSet { hUserSet    :: Set Text
                 , hChannelSet :: Set Text
                 , hSyntaxMap  :: SyntaxMap
                 }

getHighlightSet :: ChatState -> HighlightSet
getHighlightSet st =
    HighlightSet { hUserSet = Set.fromList (st^..csUsers.to allUsers.folded.uiName)
                 , hChannelSet = Set.fromList (st^..csChannels.folded.ccInfo.cdName)
                 , hSyntaxMap = st^.csResources.crSyntaxMap
                 }

getNewMessageCutoff :: ChannelId -> ChatState -> Maybe NewMessageIndicator
getNewMessageCutoff cId st = do
    cc <- st^?csChannel(cId)
    return $ cc^.ccInfo.cdNewMessageIndicator

getEditedMessageCutoff :: ChannelId -> ChatState -> Maybe ServerTime
getEditedMessageCutoff cId st = do
    cc <- st^?csChannel(cId)
    cc^.ccInfo.cdEditedMessageThreshold

data SerializedState =
    SerializedState { serializedChatState :: ChatState
                    , serializedRenderState :: Brick.RenderState Name
                    , serializedWindowSize :: DisplayRegion
                    }

instance A.ToJSON SerializedState where
    toJSON s =
        A.object [ "chatState" A..= serializedChatState s
                 , "renderState" A..= show (serializedRenderState s)
                 , "windowSize" A..= show (serializedWindowSize s)
                 ]

instance A.FromJSON SerializedState where
    parseJSON = A.withObject "SerializedState" $ \o -> do
        cs <- o A..: "chatState"
        rsStr <- o A..: "renderState"
        sizeStr <- o A..: "windowSize"
        case (,) <$> readMaybe rsStr <*> readMaybe sizeStr of
            Nothing -> fail "Invalid SerializedState"
            Just (rs, ws) -> return $ SerializedState { serializedChatState = cs
                                                      , serializedRenderState = rs
                                                      , serializedWindowSize = ws
                                                      }
