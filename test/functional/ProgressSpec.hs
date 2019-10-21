{-# LANGUAGE OverloadedStrings #-}
module ProgressSpec where

import Control.Applicative.Combinators
import Control.Lens
import Control.Monad.IO.Class
import Data.Aeson
import Data.Default
import Haskell.Ide.Engine.Config
import Language.Haskell.LSP.Test
import Language.Haskell.LSP.Messages -- TODO: Move this into haskell-lsp-types
import Language.Haskell.LSP.Types
import qualified Language.Haskell.LSP.Types.Lens as L
import Language.Haskell.LSP.Types.Capabilities
import Test.Hspec
import TestUtils

spec :: Spec
spec = describe "window/workDoneProgress" $ do
  it "sends indefinite progress notifications" $
    -- Testing that ghc-mod sends progress notifications
    runSession hieCommand progressCaps "test/testdata" $ do
      doc <- openDoc "ApplyRefact2.hs" "haskell"

      skipMany loggingNotification

      -- Initial hlint notifications
      _ <- publishDiagnosticsNotification

      createRequest <- message :: Session WorkDoneProgressCreateRequest
      liftIO $ do
        createRequest ^. L.params `shouldBe` WorkDoneProgressCreateParams (ProgressNumericToken 0)

      startNotification <- message :: Session WorkDoneProgressBeginNotification
      liftIO $ do
        startNotification ^. L.params . L.value . L.title `shouldBe` "Typechecking ApplyRefact2.hs"
        startNotification ^. L.params . L.token `shouldBe` (ProgressNumericToken 0)

      doneNotification <- skipManyTill loggingNotification (message :: Session WorkDoneProgressEndNotification)
      liftIO $ doneNotification ^. L.params . L.token `shouldBe` (ProgressNumericToken 0)

      -- the ghc-mod diagnostics
      _ <- skipManyTill loggingNotification publishDiagnosticsNotification

      -- Test incrementing ids
      sendNotification TextDocumentDidSave (DidSaveTextDocumentParams doc)

      -- hlint notifications
      _ <- skipManyTill loggingNotification publishDiagnosticsNotification

      createRequest' <- skipManyTill loggingNotification (message :: Session WorkDoneProgressCreateRequest)
      liftIO $ do
        createRequest' ^. L.params `shouldBe` WorkDoneProgressCreateParams (ProgressNumericToken 1)

      startNotification' <- message :: Session WorkDoneProgressBeginNotification
      liftIO $ do
        startNotification' ^. L.params . L.value . L.title `shouldBe` "Typechecking ApplyRefact2.hs"
        startNotification' ^. L.params . L.token `shouldBe` (ProgressNumericToken 1)

      doneNotification' <- skipManyTill loggingNotification (message :: Session WorkDoneProgressEndNotification)
      liftIO $ doneNotification' ^. L.params . L.token `shouldBe` (ProgressNumericToken 1)

      -- the ghc-mod diagnostics
      const () <$> skipManyTill loggingNotification publishDiagnosticsNotification

  it "sends indefinite progress notifications with liquid" $
    -- Testing that Liquid Haskell sends progress notifications
    runSession hieCommand progressCaps "test/testdata" $ do
      doc <- openDoc "liquid/Evens.hs" "haskell"

      skipMany loggingNotification

      -- Initial hlint notifications
      _ <- skipManyTill loggingNotification publishDiagnosticsNotification

      _ <- message :: Session  WorkDoneProgressCreateRequest
      _ <- message :: Session WorkDoneProgressBeginNotification
      _ <- message :: Session WorkDoneProgressEndNotification

      -- the ghc-mod diagnostics
      _ <- skipManyTill loggingNotification publishDiagnosticsNotification

      -- Enable liquid haskell plugin
      let config = def { liquidOn  = True, hlintOn = False }
      sendNotification WorkspaceDidChangeConfiguration (DidChangeConfigurationParams (toJSON config))

      -- Test liquid
      sendNotification TextDocumentDidSave (DidSaveTextDocumentParams doc)

      -- hlint notifications
      _ <- skipManyTill loggingNotification publishDiagnosticsNotification

      let startPred (NotWorkDoneProgressBegin m) =
            m ^. L.params . L.value . L.title == "Running Liquid Haskell on Evens.hs"
          startPred _ = False

      let donePred (NotWorkDoneProgressEnd _) = True
          donePred _ = False

      _ <- skipManyTill anyMessage $ between (satisfy startPred) (satisfy donePred) $
              many (satisfy (\x -> not (startPred x || donePred x)))
      return ()

progressCaps :: ClientCapabilities
progressCaps = fullCaps { _window = Just (WindowClientCapabilities (Just True)) }
