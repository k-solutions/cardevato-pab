{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE RankNTypes         #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE TypeOperators      #-}

module Simulator
  ( simulate
  , writeCostingScripts
  ) where

import           Control.Monad                       (void)
import           Control.Monad.Freer                 (interpret)
import           Control.Monad.IO.Class              (MonadIO (..))
import           Data.Aeson                          (FromJSON (..),
                                                      Options (..), ToJSON (..),
                                                      defaultOptions,
                                                      genericParseJSON,
                                                      genericToJSON)
import           Data.Default                        (def)
import qualified Data.OpenApi                        as OpenApi
import           GHC.Generics                        (Generic)
-- import           Plutus.Contract                     (ContractError)
-- import           Plutus.Contracts.Game               as Game
import           Plutus.PAB.Effects.Contract.Builtin (Builtin,
                                                      BuiltinHandler (contractHandler),
                                                      SomeBuiltin (..))
import qualified Plutus.PAB.Effects.Contract.Builtin as Builtin
import           Plutus.PAB.Simulator                (SimulatorEffectHandlers)
import qualified Plutus.PAB.Simulator                as Simulator
import qualified Plutus.PAB.Webserver.Server         as PAB.Server
import           Plutus.Trace.Emulator.Extract       (Command (..),
                                                      ScriptsConfig (..),
                                                      ValidatorMode (FullyAppliedValidators),
                                                      writeScriptsTo)
import           Prettyprinter                       (Pretty (..), viaShow)
-- import           Ledger.Index                        (ValidatorMode(..))
import qualified PAB
import qualified Trace
import qualified Wallet.Emulator.Wallet              as Wallet


simulate :: IO ()
simulate = void $ Simulator.runSimulationWith handlers $ do
    Simulator.logString @(Builtin PAB.TokenContracts) "Starting plutus-starter PAB webserver on port 9080. Press enter to exit."

    (wallet, _paymentPubKeyHash) <- Simulator.addWallet
    Simulator.waitNSlots 1
    liftIO $ writeFile "scripts/wallet" (show $ Wallet.getWalletId wallet)

    shutdown <- PAB.Server.startServerDebug

    -- Example of spinning up a game instance on startup
    -- void $ Simulator.activateContract (Wallet 1) GameContract
    -- You can add simulator actions here:
    -- Simulator.observableState
    -- etc.
    -- That way, the simulation gets to a predefined state and you don't have to
    -- use the HTTP API for setup.

    -- Pressing enter results in the balances being printed
    void $ liftIO getLine

    Simulator.logString @(Builtin PAB.TokenContracts) "Balances at the end of the simulation"
    b <- Simulator.currentBalances
    Simulator.logBalances @(Builtin PAB.TokenContracts) b

    shutdown

-- | An example of computing the script size for a particular trace.
-- Read more: <https://plutus.readthedocs.io/en/latest/plutus/howtos/analysing-scripts.html>
writeCostingScripts :: IO ()
writeCostingScripts = do
  let config = ScriptsConfig { scPath = "/tmp/plutus-costing-outputs/", scCommand = cmd }
      cmd    = Scripts { unappliedValidators = FullyAppliedValidators }
      -- Note: Here you can use any trace you wish.
      trace  = Trace.tokenTrace
  (totalSize, exBudget) <- writeScriptsTo config "game" trace def
  putStrLn $ "Total size = " <> show totalSize
  putStrLn $ "ExBudget = " <> show exBudget


--data StarterContracts =
--    PAB.TokenContracts
--    deriving (Eq, Ord, Show, Generic)
--    deriving anyclass OpenApi.ToSchema
--
-- NOTE: Because 'StarterContracts' only has one constructor, corresponding to
-- the demo 'Game' contract, we kindly ask aeson to still encode it as if it had
-- many; this way we get to see the label of the contract in the API output!
-- If you simple have more contracts, you can just use the anyclass deriving
-- statement on 'StarterContracts' instead:
--
--    `... deriving anyclass (ToJSON, FromJSON)`
--instance ToJSON StarterContracts where
--  toJSON = genericToJSON defaultOptions {
--             tagSingleConstructors = True }
--instance FromJSON StarterContracts where
--  parseJSON = genericParseJSON defaultOptions {
--             tagSingleConstructors = True }
--
--instance Pretty StarterContracts where
--    pretty = viaShow
--
--instance Builtin.HasDefinitions StarterContracts where
--    getDefinitions = [GameContract]
--    getSchema =  \case
--        GameContract -> Builtin.endpointsToSchemas @Game.GameSchema
--    getContract = \case
--        GameContract -> SomeBuiltin (Game.game @ContractError)
--
handlers :: SimulatorEffectHandlers (Builtin PAB.TokenContracts)
handlers =
    Simulator.mkSimulatorHandlers def
    $ interpret (contractHandler Builtin.handleBuiltin)

