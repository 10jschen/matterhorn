{-# LANGUAGE RecordWildCards #-}

module Main where

import           Prelude ()
import           Prelude.Compat

import           Brick
import           Brick.BChan
import           Control.Concurrent (forkIO)
import qualified Control.Concurrent.STM as STM
import           Control.Exception (try)
import           Control.Monad (forever, void, when)
import           Data.Monoid ((<>))
import qualified Graphics.Vty as Vty
import           Lens.Micro.Platform
import           System.Exit (exitFailure)
import           System.IO (IOMode(WriteMode), openFile, hClose)
import           Text.Aspell (stopAspell)

import           Config
import           Options
import           State.Setup
import           Events
import           Draw
import           Types
import           InputHistory

main :: IO ()
main = do
  opts <- grabOptions
  configResult <- findConfig (optConfLocation opts)
  config <- case configResult of
      Left err -> do
          putStrLn $ "Error loading config: " <> err
          exitFailure
      Right c -> return c

  eventChan <- newBChan 25
  writeBChan eventChan RefreshWebsocketEvent

  requestChan <- STM.atomically STM.newTChan
  void $ forkIO $ forever $ do
    chk <- STM.atomically $ do
              chanCopy <- STM.cloneTChan requestChan
              let cntMsgs = do m <- STM.tryReadTChan chanCopy
                               case m of
                                 Nothing -> return 0
                                 Just _ -> (1 +) <$> cntMsgs
              cntMsgs
    writeBChan eventChan $ if chk == 0 then BGIdle else BGBusy chk
    req <- STM.atomically $ STM.readTChan requestChan
    when (chk == 0) $ writeBChan eventChan $ BGBusy 1
    res <- try req
    case res of
      Left e    -> writeBChan eventChan (AsyncErrEvent e)
      Right upd -> writeBChan eventChan (RespEvent upd)

  logFile <- case optLogLocation opts of
    Just path -> Just `fmap` openFile path WriteMode
    Nothing   -> return Nothing
  st <- setupState logFile config requestChan eventChan

  let mkVty = do
        vty <- Vty.mkVty Vty.defaultConfig
        let output = Vty.outputIface vty
        Vty.setMode output Vty.BracketedPaste True
        return vty

  finalSt <- customMain mkVty (Just eventChan) app st

  case finalSt^.csEditState.cedSpellChecker of
      Nothing -> return ()
      Just s -> stopAspell s

  case logFile of
    Nothing -> return ()
    Just h -> hClose h
  writeHistory (finalSt^.csInputHistory)

app :: App ChatState MHEvent Name
app = App
  { appDraw         = draw
  , appChooseCursor = showFirstCursor
  , appHandleEvent  = onEvent
  , appStartEvent   = return
  , appAttrMap      = (^.csResources.crTheme)
  }
