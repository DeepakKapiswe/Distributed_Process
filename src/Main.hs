{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}

module Main where
import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process                        hiding
                                                                     (Message)
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node                   (initRemoteTable)
import           Control.Monad
import           Control.Monad.Primitive
import           Data.Binary
import           Data.Int
import           Data.List                                          (nub)
import           Data.Time.Clock
import           Data.Typeable
import qualified Data.Vector.Unboxed                                as V
import qualified Data.Vector.Unboxed.Mutable                        as MV
import           GHC.Generics                                       (Generic)
import           System.Environment                                 (getArgs)
import           System.Random
import           Text.Printf
import           Data.Vector.Binary


data Message = Message { 
                 val::Double
               , senderId::Int
               , sendState::V.Vector Int64
               }
 deriving (Eq,Show,Typeable,Generic)

instance Binary Message

instance Ord Message where
  compare m1@(Message _ x stateVecX) 
          m2@(Message _ y stateVecY) 
   | a <  a'  &&  b <  b' = LT
   | a == a'  &&  b <  b' = LT
   | a >  a'  &&  b == b' = GT
   | a >  a'  &&  b >  b' = GT
   | otherwise = EQ
   where
        a  = (V.!) stateVecX x
        a' = (V.!) stateVecY x
        b  = (V.!) stateVecY y
        b' = (V.!) stateVecY y

data BroadcastConfig = Config {
              initStateVec::NodeStateIM
             , bSenderId:: Int
             , bSendFor::Int
             , bSeed:: Int 
             }
 deriving (Eq,Show,Typeable,Generic)

instance Binary BroadcastConfig

type NodeStateM = MV.MVector RealWorld Int64   
type NodeStateIM = V.Vector Int64   

storeMessages::[Message]->Message->[Message]
storeMessages [] m = [m]
storeMessages l@(x:xs) m = case compare m x of
  GT -> m:l
  _   -> x:(storeMessages xs m )

mergeTwoStateVec::(PrimMonad m, MV.Unbox a, Ord a)=> (MV.MVector (PrimState m) a) -> V.Vector a -> m ( )
mergeTwoStateVec oldStateVec newMsgStateVec = V.ifoldM'_ (updateVal) oldStateVec newMsgStateVec

updateVal::(PrimMonad m, MV.Unbox a,Ord a)=>MV.MVector (PrimState m) a -> Int-> a -> m (MV.MVector (PrimState m) a)
updateVal mvector idx val = do
  oldVal <- MV.read mvector idx
  when (val > oldVal) $ MV.write mvector idx val 
  return mvector

-- | Starting process which will run on each node
--   it spawns a thread for broadcasting messages
--   and accumulates the results
startNodeProcess::BroadcastConfig->Process ()
startNodeProcess (Config nodeStateVecIM senderId sendFor seed) = do
  p <- getSelfPid
  say $ "Started process " ++ show p

  nodeStateVecM <- liftIO $ V.unsafeThaw nodeStateVecIM
  pids <- expect ::Process [ProcessId]
  
  currentTime <- liftIO getCurrentTime
  let randomList = randomRs (0::Double,1::Double) (mkStdGen seed)
      sendingTime = addUTCTime (fromIntegral sendFor) currentTime

  spawnLocal $ sendMsg nodeStateVecM senderId sendingTime randomList pids
  accumulateIncomingMsgs nodeStateVecM 0 [] []

-- | The accumulating process, It runs on each node and
--   all other nodes send messages to them and they accumutale
--   the results and decide when to print the results if got
--   any signal.They perform only receiving task
accumulateIncomingMsgs::NodeStateM->Int->[Message]->[NodeId]->Process ()
accumulateIncomingMsgs nodeStateVec count acc nodes =
   receiveWait [
            match $ \m@(Message d sid sState::Message) -> do
              say . show $  sState
              liftIO $ mergeTwoStateVec nodeStateVec sState
              accumulateIncomingMsgs nodeStateVec (count +1) (m:acc) nodes,
            match $ \(node::NodeId,totalNodes::Int)->
              if (length.nub $ node:nodes)==totalNodes then
                  say $ unlines ["\ntotal messages : " ++ show count,
                      "sigma : " ++ (show .sum .zipWith (*) [1..] $ val <$>acc)]
                else
                accumulateIncomingMsgs nodeStateVec count acc (node:nodes)
              ]

-- | sendMsg checks the current time of the node
--   and sends proper signal (in the form of different type of message)
--   to the receiving process that sending time has expired, else
--   it send the head of the random number list
--   to the receiving nodes (processes) and this cycles continues
sendMsg::NodeStateM->Int->UTCTime->[Double]->[ProcessId]->Process ()
sendMsg nodeStateVecM senderId stoppingTime rNums pids = do
  currentTime <- liftIO getCurrentTime
  if currentTime >= stoppingTime then do
       node <- getSelfNode
       let allNodeCount = length pids
       void $ spawnLocal (forM_ pids $ \p -> send p (node,allNodeCount))
      else do
         forM_ pids $ \p -> do
           liftIO $ MV.modify nodeStateVecM  (+1) senderId 
           sState <- liftIO $ V.freeze nodeStateVecM
           send p (Message (head rNums) senderId sState) 
         sendMsg nodeStateVecM senderId stoppingTime (tail rNums) pids

-- | entry in static remote table of our functions for
--   run time accese by every node
remotable ['startNodeProcess]


-- | our Static remote table
myRemoteTable :: RemoteTable
myRemoteTable = Main.__remoteTable initRemoteTable

-- | master will start actual program execution with
--   starting all the slave nodes and also terminating
--   after correct time if not done

master :: Int->Int->Int->Backend -> [NodeId] -> Process ()
master sendFor waitFor seed backend slaves = do
  say "Master Node Started"
  mnode<-getSelfNode
  
  let allNodeCount = length slaves + 1
      nodeStateVecs = replicate allNodeCount $ V.replicate allNodeCount (0::Int64)
      configs = zipWith3 (\v sid seed-> Config v sid sendFor seed) nodeStateVecs [0..] [seed..] 
      nodesAndConfigs = zip (mnode:slaves) configs

  pids <- forM nodesAndConfigs $ \(node,conf) -> 
    spawn node $ $(mkClosure 'startNodeProcess) conf
  forM_ pids $ \pid -> send pid pids
  
  say "All Nodes Started"
  say $ printf "sending messages for %d seconds" sendFor
  liftIO. threadDelay $ 1000000 * sendFor
  say $ printf "waiting for printing the results %d seconds" waitFor
  liftIO. threadDelay $ 1000000 * waitFor
  terminateAllSlaves backend

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["master", host, port,"--send-for",k,"--wait-for",l,"--with-seed",s] -> do
      backend <- initializeBackend host port myRemoteTable
      startMaster backend (master (read k) (read l) (read s) backend)
    ["slave", host, port] -> do
      backend <- initializeBackend host port myRemoteTable
      startSlave backend
    _-> print "Please provide valid arguments"

-- Note : no importance is given on polishing the code with
--        parsing and handling the arguments in a nice way
