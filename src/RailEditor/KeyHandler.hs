{- |
Module      :  KeyHandler.hs
Description :  .
Maintainer  :  Kelvin Glaß, Chritoph Graebnitz, Kristin Knorr, Nicolas Lehmann (c)
License     :  MIT

Stability   :  experimental

The KeyHandler-module allows to react on keypress-events in the editor.
-}
module KeyHandler (
                   handleKey   -- handles keypress-events
                  )
  where

    -- imports --
    import qualified RedoUndo
    import qualified Highlighter
    -- other modules that depict editor-functions should be imported here

    -- functions --

    -- handles keypress-events
    --handleKey :: ?
    handleKey = undefined   -- TODO: implement this functions
