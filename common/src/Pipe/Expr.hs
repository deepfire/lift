{-# LANGUAGE OverloadedStrings #-}
module Pipe.Expr
  ( Expr(..)
  , parse
  , indexLocated
  , lookupLocated
  , parseExpr
  )
where

import Control.Applicative (some)
import Control.Monad (foldM)
import Data.Either (partitionEithers)
import qualified Data.IntervalMap.FingerTree            as IMap

import Text.Megaparsec (runParserT, eof)
import Text.Megaparsec.Char (string)
import Text.Megaparsec.Parsers (unParsecT, sepBy1)
import Text.Parser.Token

import Data.Parsing
-- import Debug.TraceErr
import Basis
import Type
import Ground.Parser (parseQName', holeToken) -- No Ground needed.
import Ground.Table (parseSomeValue)          -- Needs Ground.
import Pipe.Types


data Expr p where
  PVal  ::
    { vX  :: SomeValue
    } -> Expr p
  PPipe ::
    { pP  :: p
    } -> Expr p
  PApp ::
    { apF :: Expr p
    , apX :: Expr p
    } -> Expr p
  PComp ::
    { coF :: Expr p
    , coG :: Expr p
    } -> Expr p
  deriving (Foldable, Functor, Traversable)


parse :: Text -> Either Text (Expr (Located (QName Pipe)))
parse = parse' parseQName'

indexLocated :: Foldable f => f (Located a)
             -> IMap.IntervalMap Int a
indexLocated =
  foldMap (\Locn{locSpan, locVal} ->
             IMap.singleton locSpan locVal)

lookupLocated
  :: Int -> IMap.IntervalMap Int a
  -> Maybe a
lookupLocated col imap =
  case IMap.search col imap of
    [] -> Nothing
    (_, x):_ -> Just x

parse'
  :: forall e n. (e ~ Text)
  => (Bool -> Parser n)
  -> Text
  -> Either e (Expr n)
parse' nameParser = tryParse True
 where
   tryParse :: Bool -> Text -> Either e (Expr n)
   tryParse mayExtend s =
     case (,)
          (runIdentity $ runParserT
           (do
               x <- unParsecT $ parseExpr (nameParser (not mayExtend))
               eof
               pure x)
            "" s)
          mayExtend
     of
       -- If parse succeeds, then propagate immediately.
       (Right (Right x), _)     -> Right x
       -- If we don't parse, and we can't extend, then fail immediately.
       (Left         e,  False) -> Left $ "Pipe expr parser: " <> pack (show e)
       (Right (Left  e), False) -> Left $ pack (show e)
       -- If we don't parse, and we can extend, then retry with extension allowed.
       (_,               True)  -> tryParse False (s <> holeToken)

parseExpr
  :: forall e n
  . ( e ~ Text)
  => Parser n
  -> Parser (Either e (Expr n))
parseExpr nameParser =
  comps
 where
   term
     =   parens comps
     <|> (pure . PVal  <$> parseSomeValue)
     <|> (pure . PPipe <$> nameParser)
   applys = do
     xss <- some term
     case xss of
       x : xs -> foldM (\l r -> pure $ PApp <$> l <*> r) x xs
       _ -> error "Invariant failed: 'some' failed us."
   comps = do
     xs' <- sepBy1 applys (token (string "."))
     let (errs, xs) = partitionEithers xs'
     pure $ if null errs
       then Right $ foldl1 PComp xs
       else Left (pack . show $ head errs)

{-------------------------------------------------------------------------------
  Boring.
-------------------------------------------------------------------------------}
instance Show p => Show (Expr p) where
  show (PVal    x) =   "Val "<>show x
  show (PPipe   x) =  "Pipe "<>show x
  show (PApp  f x) =  "App ("<>show f<>") ("<>show x<>")"
  show (PComp f g) = "Comp ("<>show f<>") ("<>show g<>")"
