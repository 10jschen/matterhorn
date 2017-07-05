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
import           Data.Maybe (isNothing)
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
    chk <- STM.atomically $ STM.tryPeekTChan requestChan
    when (isNothing chk) $ writeBChan eventChan BGIdle
    req <- STM.atomically $ STM.readTChan requestChan
    when (isNothing chk) $ writeBChan eventChan BGBusy
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
