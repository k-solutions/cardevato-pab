{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Token.OffChain
    ( TokenParams (..)
    , MintSchema
    , adjustAndSubmit, adjustAndSubmitWith
    , endpoints
    , mintToken
    ) where

import           Control.Monad          hiding (fmap)
import           Data.Aeson             (FromJSON, ToJSON)
import qualified Data.Map               as Map
import           Data.Maybe             (fromJust)
import           Data.OpenApi.Schema    (ToSchema)
import           Data.Text              (Text, pack)
import           Data.Void              (Void)
import           GHC.Generics           (Generic)
import           Ledger                 hiding (mint, singleton)
import qualified Ledger.Constraints     as Constraints
import qualified Ledger.Typed.Scripts   as Scripts
import           Ledger.Value           as Value
import           Plutus.Contract        (Contract (..))
import qualified Plutus.Contract        as Contract
import           Plutus.Contract.Wallet (getUnspentOutput)
import qualified Plutus.V2.Ledger.Api   as PLA.V2
import qualified PlutusTx
import           PlutusTx.Prelude       hiding (Semigroup (..), unless)
import           Prelude                (Semigroup (..), Show (..), String)
import qualified Prelude
import           Text.Printf            (printf)
import           Token.OnChain
import           Utils                  (getCredentials)


data TokenParams = TokenParams
    { tpToken   :: !TokenName
    , tpAddress :: !Address
    } deriving (Prelude.Eq, Prelude.Ord, Generic, FromJSON, ToJSON, ToSchema, Show)

type MintSchema = Contract.Endpoint "mint" TokenParams
-- mkSchemaDefinitions ''MintSchema

adjustAndSubmitWith :: ( PlutusTx.FromData (Scripts.DatumType a)
                       , PlutusTx.ToData (Scripts.RedeemerType a)
                       , PlutusTx.ToData (Scripts.DatumType a)
                       , Contract.AsContractError e
                       )
                    => Constraints.ScriptLookups a
                    -> Constraints.TxConstraints (Scripts.RedeemerType a) (Scripts.DatumType a)
                    -> Contract w s e CardanoTx
adjustAndSubmitWith lookups constraints = do
    unbalanced <- Contract.adjustUnbalancedTx =<< Contract.mkTxConstraints lookups constraints
    Contract.logDebug @String $ printf "unbalanced: %s" $ show unbalanced
    unsigned <- Contract.balanceTx unbalanced
    Contract.logDebug @String $ printf "balanced: %s" $ show unsigned
    signed <- Contract.submitBalancedTx unsigned
    Contract.logDebug @String $ printf "signed: %s" $ show signed
    return signed

adjustAndSubmit :: ( PlutusTx.FromData (Scripts.DatumType a)
                   , PlutusTx.ToData (Scripts.RedeemerType a)
                   , PlutusTx.ToData (Scripts.DatumType a)
                   , Contract.AsContractError e
                   )
                => Scripts.TypedValidator a
                -> Constraints.TxConstraints (Scripts.RedeemerType a) (Scripts.DatumType a)
                -> Contract w s e CardanoTx
adjustAndSubmit = adjustAndSubmitWith . Constraints.typedValidatorLookups

mintToken :: TokenParams -> Contract w MintSchema Text CurrencySymbol
mintToken tp = do
    Contract.logDebug @String $ printf "started minting: %s" $ show tp
    let addr = tpAddress tp
    case getCredentials addr of
        Nothing      -> Contract.throwError $ pack $ printf "expected pubkey address, but got %s" $ show addr
        Just (x, my) -> do
            oref <- getUnspentOutput
            o    <- fromJust <$> Contract.txOutFromRef oref
            Contract.logDebug @String $ printf "picked UTxO at %s with value %s" (show oref) (show $ _ciTxOutValue o)

            let tn          = tpToken tp
                cs          = tokenCurSymbol
                val         = Value.singleton cs tn 1
                toRedeemer  = PLA.V2.Redeemer
                            . PLA.V2.dataToBuiltinData
                            . PLA.V2.toData
                c           = case my of
                    Nothing -> Constraints.mustPayToPubKey x val
                    Just y  -> Constraints.mustPayToPubKeyAddress x y val
                lookups     =  Constraints.plutusV2MintingPolicy tokenPolicy
                            <> Constraints.unspentOutputs (Map.singleton oref o)
                constraints =  Constraints.mustMintValueWithRedeemer (toRedeemer oref) val
                            <> Constraints.mustSpendPubKeyOutput oref
                            <> c

            void $ adjustAndSubmitWith @Void lookups constraints
            Contract.logInfo @String $ printf "minted %s" (show val)
            return cs

endpoints :: Contract () MintSchema Text ()
endpoints = mint' >> endpoints
  where mint' = Contract.awaitPromise $ Contract.endpoint @"mint" mintToken

