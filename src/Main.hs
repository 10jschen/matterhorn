{-# LANGUAGE RecordWildCards #-}

module Main where

import           Prelude ()
import           Prelude.Compat
import           Brick
import           Control.Concurrent (forkIO)
import qualified Control.Concurrent.Chan as Chan
import           Control.Monad (forever)
import           Data.Default (def)
import           Data.Monoid ((<>))
import qualified Graphics.Vty as Vty
import           Lens.Micro.Platform
import           System.Exit (exitFailure)
import           System.IO (IOMode(WriteMode), openFile, hClose)

import           Config
import           Options
import           State
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

  eventChan <- Chan.newChan
  Chan.writeChan eventChan RefreshWebsocketEvent

  requestChan <- Chan.newChan
  _ <- forkIO $ forever $ do
    req <- Chan.readChan requestChan
    upd <- req
    Chan.writeChan eventChan (RespEvent upd)

  logFile <- case optLogLocation opts of
    Just path -> Just `fmap` openFile path WriteMode
    Nothing   -> return Nothing
  st <- setupState logFile config requestChan eventChan

  let mkVty = do
        vty <- Vty.mkVty def
        let output = Vty.outputIface vty
        Vty.setMode output Vty.BracketedPaste True
        return vty

  finalSt <- customMain mkVty eventChan app st
  case logFile of
    Nothing -> return ()
    Just h -> hClose h
  writeHistory (finalSt^.csInputHistory)

app :: App ChatState Event Name
app = App
  { appDraw         = draw
  , appChooseCursor = showFirstCursor
  , appHandleEvent  = onEvent
  , appStartEvent   = updateChannelScrollState
                      -- ^ Critical to ensure that we scroll to the
                      -- bottom of the initially-viewed channel.
  , appAttrMap      = (^.csTheme)
  , appLiftVtyEvent = VtyEvent
  }
