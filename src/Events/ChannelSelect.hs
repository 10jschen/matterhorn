{-# LANGUAGE QuasiQuotes #-}

module Events.ChannelSelect where

import Prelude ()
import Prelude.Compat

import Data.Monoid ((<>))
import qualified Data.Text as T
import qualified Data.HashMap.Strict as HM
import qualified Graphics.Vty as Vty
import Lens.Micro.Platform

import Types
import State

onEventChannelSelect :: Vty.Event -> MH ()
onEventChannelSelect e | Just kb <- lookupKeybinding e channelSelectKeybindings =
    kbAction kb
onEventChannelSelect (Vty.EvKey Vty.KBS []) = do
    csChannelSelectString %= (\s -> if T.null s then s else T.init s)
    updateChannelSelectMatches
onEventChannelSelect (Vty.EvKey (Vty.KChar c) []) | c /= '\t' = do
    csChannelSelectString %= (flip T.snoc c)
    updateChannelSelectMatches
onEventChannelSelect _ = return ()

channelSelectKeybindings :: [Keybinding]
channelSelectKeybindings =
    [ [key|Enter Select matching channel|] $ do
             -- If there is only one channel selection match, switch to
             -- it
             st <- use id
             let allMatches = (HM.elems $ st^.csChannelSelectChannelMatches) <>
                              (HM.elems $ st^.csChannelSelectUserMatches)
                 matchingName = (==) (st^.csChannelSelectString) . channelNameFromMatch
                 exactMatches = filter matchingName allMatches
             case (allMatches, exactMatches) of
                 ([single], _) -> do
                     csMode .= Main
                     changeChannel (channelNameFromMatch single)
                 (_, [exact]) -> do
                     csMode .= Main
                     changeChannel (channelNameFromMatch exact)
                 _ -> return ()

    , [key|Esc Cancel channel selection|] (csMode .= Main)
    , [key|C-c Cancel channel selection|] (csMode .= Main)
    ]
