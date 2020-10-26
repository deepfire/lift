{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Reflex.Vty.Widget.Extra
  ( module Reflex.Vty.Widget.Extra
  ) where

import           Safe

import           Control.Arrow ((>>>), (&&&))
import           Control.Monad
import           Control.Monad.Fix
import           Control.Monad.NodeId

import           Data.Function
import           Data.Functor ((<&>))
import           Data.List                             as List
import           Data.Maybe (fromMaybe)
import           Data.Text (Text, pack, unpack)
import           Data.Text.Zipper
import           Data.Text.Zipper.Extra

import           Reflex
import           Reflex.Network
import           Reflex.Vty.Widget                 hiding (text)
import           Reflex.Vty.Widget.Input.RichText
import           Reflex.Vty.Widget.Layout

import qualified Graphics.Vty as V

import           Basis hiding (Dynamic, left, right)

import Debug.Reflex


type ReflexVty t m =
  ( Adjustable t m
  , MonadFix m
  , MonadHold t m
  , MonadNodeId m
  , NotReady t m
  , PostBuild t m
  , Reflex t
  )

newtype Width  = Width  { unWidth  :: Int }
newtype Height = Height { unHeight :: Int }
newtype Index  = Index  { unIndex  :: Int } deriving Show
newtype Column = Column { unColumn :: Int } deriving Show


-- XXX:  efficiency of fmap (fmap Just . leftmost) over 100+ elts?

upDownNavigation :: (Reflex t, Monad m) => VtyWidget t m (Event t Int)
upDownNavigation = do
  fwd  <- fmap (const   1)  <$> key V.KDown
  back <- fmap (const (-1)) <$> key V.KUp
  return $ leftmost [fwd, back]

selecting :: Reflex t => (V.Attr -> V.Attr) -> Behavior t V.Attr -> Behavior t Bool -> Behavior t V.Attr
selecting attrXform attrB selB = comp <$> attrB <*> selB
  where
    comp attr False = attr
    comp attr True  = attrXform attr

richTextStatic :: ReflexVty t m => V.Attr -> Behavior t Text -> VtyWidget t m ()
richTextStatic = richText . RichTextConfig . pure

fixedInert
  :: (Reflex t, Monad m, MonadNodeId m)
  => Dynamic t Int
  -> VtyWidget t m a
  -> Layout t m a
fixedInert sz =
  tile (TileConfig
         { _tileConfig_constraint = Constraint_Fixed <$> sz
         , _tileConfig_focusable  = pure False
         })
  . clickable

clickable
  :: (Reflex t, Monad m)
  => VtyWidget t m a
  -> VtyWidget t m (Event t (), a)
clickable child = do
  click <- mouseDown V.BLeft
  a <- child
  return (() <$ click, a)

-- * Attributery
--
foregro :: V.Color -> V.Attr
foregro = V.withForeColor V.defAttr

--------------------------------------------------------------------------------
-- * Focus button
--
data FocusButton t a =
  FocusButton
  { fbPress   :: !(Event t a)
  , fbFocused :: !(Event t a)
  }

focusButton
  :: (Reflex t, MonadHold t m, MonadFix m, MonadNodeId m)
  => (a -> Behavior t Bool -> VtyWidget t m a)
  -> a
  -> VtyWidget t m (FocusButton t a)
focusButton child a = do
  f <- focus
  focused <- scanDynMaybe
             (const (False, a))
             (curry $ \case
                 (True, (False, _)) -> Just (True, a)
                 _ -> Nothing)
             f
  void $ child a (current f)
  m <- mouseUp
  k <- key V.KEnter
  pure FocusButton
    { fbPress   = leftmost [a <$ k, a <$ m]
    , fbFocused = a <$ updated focused
    }
