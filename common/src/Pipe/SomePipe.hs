{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE UndecidableSuperClasses    #-}
{-# OPTIONS_GHC -fprint-explicit-kinds -fprint-explicit-foralls -Wno-orphans -Wno-unticked-promoted-constructors #-}
module Pipe.SomePipe
  ( SomePipe(..)
  , somePipeSetQName
  , somePipeQName
  , somePipeName
  , somePipeSig
  , withSomePipe
  , somePipeRep
  , somePipeUncons
  , somePipeOutSomeTagType
  , Result
  , PipeFunTy
  )
where

import qualified Data.SOP                         as SOP

import Basis
import Type
import Pipe.Pipe

--------------------------------------------------------------------------------
-- * Key types
--
-- | A wrapped cartesian product of all possible kinds of 'Pipe's:
--   - wire-transportable types (constrained 'Ground') vs. 'Top'-(un-)constrained
--   - saturated vs. unsaturated.
data SomePipe (p :: *)
  = forall (kas :: [*]) (o :: *). (PipeConstr  Ground kas o) =>
    G
    { spQName :: !(QName Pipe)
    , gPipe   :: !(Pipe Ground (kas :: [*]) (o :: *) (p :: *))
    }
  | forall (kas :: [*]) (o :: *). (PipeConstr  Top    kas o) =>
    T
    { spQName :: !(QName Pipe)
    , tPipe   :: !(Pipe Top    (kas :: [*]) (o :: *) (p :: *))
    }

-- | Result of running a pipe.
type Result a = IO (Either Text a)

--------------------------------------------------------------------------------
-- * SomePipe
--
pattern GPipeD, TPipeD :: Name Pipe -> ISig -> Struct -> SomeTypeRep -> SomePipe p
pattern GPipeD name sig str rep <- G _ (PipeD name sig str rep _ _ _)
pattern TPipeD name sig str rep <- T _ (PipeD name sig str rep _ _ _)

somePipeSetQName :: QName Pipe -> SomePipe p -> SomePipe p
somePipeSetQName x (G _ p) = G x p
somePipeSetQName x (T _ p) = T x p

somePipeQName :: SomePipe p -> QName Pipe
somePipeQName = spQName

somePipeName :: SomePipe p -> Name Pipe
somePipeName (GPipeD name _ _ _) = coerceName name
somePipeName (TPipeD name _ _ _) = coerceName name
somePipeName _ = error "impossible somePipeName"

somePipeSig :: SomePipe p -> ISig
somePipeSig  (GPipeD _ sig _ _) = sig
somePipeSig  (TPipeD _ sig _ _) = sig
somePipeSig _ = error "impossible somePipeSig"

somePipeRep :: SomePipe p -> SomeTypeRep
somePipeRep p = withSomePipe p pipeRep

withSomePipe
  :: forall (p :: *) (a :: *)
   . SomePipe p
  -> (forall (c :: * -> Constraint) (kas :: [*]) (o :: *)
      . (PipeConstr c kas o)
      => Pipe c kas  o  p -> a)
  -> a
withSomePipe G{..} = ($ gPipe)
withSomePipe T{..} = ($ tPipe)

somePipeUncons
  :: forall (p :: *) (e :: *)
  . ()
  => SomePipe p
  -> (forall (c :: * -> Constraint) (o :: *) (kas :: [*])
      . (PipeConstr c kas o, kas ~ '[])
      => Pipe c '[] o p -> e)
  -> (forall (c :: * -> Constraint) (o :: *)
             (ka :: *) (kas' :: [*])
      . (PipeConstr c (ka:kas') o, PipeConstr c kas' o)
      => Pipe c (ka:kas') o p -> Either e (Pipe c kas' o p))
  -> Either e (SomePipe p)
somePipeUncons (G _ p@(Pipe Desc {pdArgs = SOP.Nil   } _)) nil _  = Left $ nil p
somePipeUncons (G h p@(Pipe Desc {pdArgs = _ SOP.:* _} _)) _ cons = G h <$> cons p
somePipeUncons (T _ p@(Pipe Desc {pdArgs = SOP.Nil   } _)) nil _  = Left $ nil p
somePipeUncons (T h p@(Pipe Desc {pdArgs = _ SOP.:* _} _)) _ cons = T h <$> cons p

somePipeOutSomeTagType :: SomePipe p -> (SomeTag, SomeTypeRep)
somePipeOutSomeTagType p =
  withSomePipe p pipeOutSomeTagType

-- XXX: We risk equating different pipes with same names and types.
instance Eq (SomePipe p) where
  l' == r' =
    withSomePipe l' $ \(pDesc -> l) ->
    withSomePipe r' $ \(pDesc -> r) ->
      (pdRep    l  == pdRep      r) &&
      (pdName   l  == pdName     r) &&
      (pdStruct l  == pdStruct   r)

-- XXX: We risk equating different pipes with same names and types.
instance Ord (SomePipe p) where
  l' `compare` r' =
    withSomePipe l' $ \(pDesc -> l) ->
    withSomePipe r' $ \(pDesc -> r) ->
      pdRep l `compare` pdRep    r

instance Read (SomePipe ()) where
  readPrec = failRead

instance Functor SomePipe where
  fmap f (G h x) = G h (f <$> x)
  fmap f (T h x) = T h (f <$> x)

instance Show (SomePipe p) where
  show (G _ p) = "GPipe "<>unpack (showPipe p)
  show (T _ p) = "TPipe "<>unpack (showPipe p)

--------------------------------------------------------------------------------
-- * Result
--
type family PipeFunTy (as :: [*]) (o :: *) :: * where
  PipeFunTy '[]    o = Result (ReprOf o)
  PipeFunTy (x:xs) o = ReprOf x -> PipeFunTy xs o

-- withSomePipe'
--   :: forall (p :: *)
--   .  SomePipe p
--   -> (forall (c :: * -> Constraint)
--              (kas  :: [*]) (o  :: *)
--              (kas' :: [*]) (o' :: *)
--       . (PipeConstr c kas o)
--       =>  Pipe c kas  o  p
--       -> (Pipe c kas' o' p -> SomePipe p)
--       -> SomePipe p)
--   -> SomePipe p
-- withSomePipe' (G x) f = f x G
-- withSomePipe' (T x) f = f x T
-- withSomePipe'
--   :: forall (p :: *)
--   .  SomePipe p
--   -> (forall (c :: * -> Constraint)
--              (kas  :: [*]) (o  :: *)
--              (kas' :: [*]) (o' :: *)
--       . (PipeConstr c kas o, PipeConstr c kas' o')
--       =>  Pipe c kas  o  p
--       -> (Pipe c kas' o' p -> SomePipe p)
--       -> SomePipe p)
--   -> SomePipe p
-- withSomePipe' (G x) f = f x G
-- withSomePipe' (T x) f = f x T

--- A useless function : -/
-- mapSomePipeEither
--   :: forall (e :: *) (p :: *) -- (kas' :: [*])
--   .  --(All Typeable kas', All PairTypeable kas')
--      ()
--   => SomePipe p
--   -> (forall (c :: * -> Constraint) (kas :: [*]) (kas' :: [*]) (o :: *)
--       . (PipeConstr c kas o, PipeConstr c kas' o)
--       => (Proxy c -> NP (SOP.K ()) kas -> Proxy o -> NP (SOP.K ()) kas')
--       -> Pipe c kas o p
--       -> Either e (Pipe c kas' o p))
--   -> Either e (SomePipe p)
-- mapSomePipeEither (G x) f = G <$> f tf x
--   where
--     tf :: Proxy c -> NP (SOP.K ()) kas -> Proxy o -> NP (SOP.K ()) kas'
--     tf c (_ SOP.:* xs) o = xs
-- mapSomePipeEither (T x) f = T <$> f Proxy x
