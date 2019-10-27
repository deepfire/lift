module NodeEditor.Event.Processor where

import           Control.Concurrent.MVar
import           Control.Exception                      (SomeException, handle)
import           Data.Monoid                            (Last (..))
import           GHCJS.Prim                             (JSException)

import           Common.Action.Command                  (Command, execCommand, runCommand)
import           Common.Prelude
import           Common.Report                          (error)
import           NodeEditor.Action.State.App            (renderIfNeeded)
import           NodeEditor.Action.State.NodeEditor     (getSearcher)
import           NodeEditor.Event.Event                 (Event)
import qualified NodeEditor.Event.Event                 as Event
import           NodeEditor.Event.Filter                (filterEvents)
import           NodeEditor.Event.Loop                  (LoopRef)
import qualified NodeEditor.Event.Loop                  as Loop
import qualified NodeEditor.Event.Preprocessor.Batch    as BatchEventPreprocessor
import qualified NodeEditor.Event.Preprocessor.Shortcut as ShortcutEventPreprocessor
import           NodeEditor.Event.Source                (AddHandler (..))
import qualified NodeEditor.Event.Source                as JSHandlers
import qualified NodeEditor.Event.UI                    as Event
import qualified NodeEditor.Handler.App                 as App
import qualified NodeEditor.Handler.Backend.Control     as Control
import qualified NodeEditor.Handler.Backend.Graph       as Graph
import qualified NodeEditor.Handler.Breadcrumbs         as Breadcrumbs
import qualified NodeEditor.Handler.Camera              as Camera
import qualified NodeEditor.Handler.Clipboard           as Clipboard
import qualified NodeEditor.Handler.Connect             as Connect
import qualified NodeEditor.Handler.ConnectionPen       as ConnectionPen
import qualified NodeEditor.Handler.MockMonads          as MockMonads
import qualified NodeEditor.Handler.MultiSelection      as MultiSelection
import qualified NodeEditor.Handler.Navigation          as Navigation
import qualified NodeEditor.Handler.Node                as Node
import qualified NodeEditor.Handler.Port                as Port
import qualified NodeEditor.Handler.Searcher            as Searcher
import qualified NodeEditor.Handler.Sidebar             as Sidebar
import qualified NodeEditor.Handler.Undo                as Undo
import qualified NodeEditor.Handler.Visualization       as Visualization
import           NodeEditor.State.Global                (State)
import qualified NodeEditor.React.Event.App             as Event
import qualified NodeEditor.React.Event.Port            as Port

import qualified JavaScript.WebSockets                  as WS
import qualified Lift.Client                            as Lift

import Debug.Trace (trace)

actions :: LoopRef -> [Event -> Maybe (Command State ())]
actions loop =
    [ App.handle
    , Breadcrumbs.handle
    , Camera.handle
    , Clipboard.handle
    , Connect.handle
    , ConnectionPen.handle
    , Control.handle
    , Graph.handle
    , MultiSelection.handle
    , Navigation.handle
    , Node.handle
    , Port.handle
    , Sidebar.handle
    , Searcher.handle (scheduleEvent loop)
    , Undo.handle
    , Visualization.handle
    , MockMonads.handle
    ]

runCommands :: [Event -> Maybe (Command State ())] -> Event -> Command State ()
runCommands cmds event = sequence_ . catMaybes $ fmap ($ event) cmds

preprocessEvent :: Bool -> Event -> IO Event
preprocessEvent hasSearcher ev = do
    let batchEvent    = BatchEventPreprocessor.process ev
        shortcutEvent = ShortcutEventPreprocessor.process hasSearcher ev
    return $ fromMaybe ev $ getLast $
      --Last batchEvent <>
      Last shortcutEvent

processEvent :: LoopRef -> Event -> IO ()
processEvent loop ev = handle handleAnyException $ modifyMVar_ (loop ^. Loop.state) $ \state -> do
  (searcher, _) <- runCommand getSearcher state
  realEvent <- case searcher of
    Nothing -> preprocessEvent False ev
    Just _  -> preprocessEvent True  ev -- pure ev
  -- case realEvent of
  --   Event.UI (Event.AppEvent  Event.MouseMove{}) -> pure ()
  --   Event.UI (Event.PortEvent Port.MouseEnter{}) -> pure ()
  --   Event.UI (Event.PortEvent Port.MouseLeave{}) -> pure ()
  --   ev -> warn "processEvent" (show ev<>"\n→ "<>show realEvent)
  filterEvents state realEvent $ do
    handle (handleExcept state realEvent) $
      execCommand (runCommands (actions loop)
                    (trace ("handling "<> show realEvent) realEvent)
                   >> renderIfNeeded) state

connectEventSources :: LoopRef -> IO ()
connectEventSources loop = do
    let handlers = [ JSHandlers.movementHandler
                   -- , Lift.webSocketHandler ws
                   -- , JSHandlers.sceneResizeHandler
                   -- , JSHandlers.atomHandler
                   ]
        mkSource (AddHandler rh) = rh $ scheduleEvent loop
    sequence_ $ mkSource <$> handlers

handleAnyException :: SomeException -> IO ()
handleAnyException = error . show

handleExcept :: State -> Event -> JSException -> IO State
handleExcept oldState event except = do
    error $ "JavaScriptException: " <> show except <> "\n\nwhile processing: " <> show event
    return oldState


scheduleEvent :: LoopRef -> Event -> IO ()
scheduleEvent loop = Loop.schedule loop . processEvent loop

scheduleInit :: LoopRef -> IO ()
scheduleInit loop = scheduleEvent loop Event.Init
