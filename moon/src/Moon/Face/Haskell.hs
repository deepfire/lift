{-# LANGUAGE DeriveGeneric              #-}
--{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving         #-}
--{-# LANGUAGE UndecidableInstances       #-}

module Moon.Face.Haskell
  (
  -- Generic-ish
    FileName(..)
  , Loc(..)
  , URL(..)
  -- Atomics
  , IndexName(..)
  , RepoName(..)
  , PackageName(..)
  , ModuleName(..)
  , DefName(..)
  -- Composites
  , Index(..)
  , Repo(..)
  , Package(..)
  , Module(..)
  , DefType(..)
  , Def(..)
  , )
where

import Algebra.Graph
import Data.Binary
import Data.Map
import Data.Set
import Data.String
import Data.Text
import GHC.Generics

{-------------------------------------------------------------------------------
  Generic types for externalisation
-------------------------------------------------------------------------------}
newtype URL        = URL        Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
newtype FileName   = FileName   Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
-- | 1:1 translation of RealSrcSpan
data Loc
  =  Loc
     { srcSpanFile   :: !FileName,
       srcSpanSLine  :: {-# UNPACK #-} !Int,
       srcSpanSCol   :: {-# UNPACK #-} !Int,
       srcSpanELine  :: {-# UNPACK #-} !Int,
       srcSpanECol   :: {-# UNPACK #-} !Int
     }
     deriving (Generic, Show)
instance Binary  Loc

{-------------------------------------------------------------------------------
  Atomics
-------------------------------------------------------------------------------}
newtype IndexName   = IndexName   Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
newtype RepoName    = RepoName    Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
newtype PackageName = PackageName Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
newtype ModuleName  = ModuleName  Text deriving (Binary, Eq, Generic, IsString, Ord, Show)
newtype DefName     = DefName     Text deriving (Binary, Eq, Generic, IsString, Ord, Show)

{-------------------------------------------------------------------------------
  Composites
-------------------------------------------------------------------------------}
-- | Package index -- something we might consult for a package's URL.
data Index = Index
  { ixName           :: !IndexName
  , ixURL            :: !URL
  , ixPackages       :: Map PackageName URL
  } deriving (Generic, Show)
instance Binary Index

data Repo = Repo
  { repoName         :: !RepoName
  , repoURLs         :: Set URL
  , repoPackages     :: Map PackageName Package
  } deriving (Generic, Show)
instance Binary Repo

-- Not strict, since there's a hope of making it actually lazy.
data Package = Package
  { pkgName          :: !PackageName
  , pkgModules       :: Map ModuleName Module
  , pkgModuleDeps    :: Graph Module
  , pkgDeps          :: Set PackageName
  } deriving (Generic, Show)
instance Binary Package
deriving instance (Generic (Graph Module))
instance Binary (Graph Module)

data Module = Module
  { modName          :: !ModuleName
  , modDefs          :: !(Map DefName Def)
  } deriving (Generic, Show)
instance Binary Module

data Def = Def
  { defType          :: !DefType
  , defName          :: !DefName
  , defLoc           :: !Loc
  } deriving (Generic, Show)
instance Binary Def

data DefType
  = TypeSyn
  | TypeFam
  | DataFam
  | Data
  | Class
  | ClassInst !DefName
  | Fun
  | Var
  | Foreign
  deriving (Eq, Generic, Show)
instance Binary DefType

