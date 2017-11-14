{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}

module Main where
import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process                hiding  (Message)
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node                   (initRemoteTable)
import           Control.Monad 
import           Control.Monad.Primitive
import           Data.Binary
import           Data.Int                                           (Int64)
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

-- | Our Message Type which consists of the 
--   actual val (random number)
--   senderId is the index representing node in sendState
--   sendState is the Known State of whole system according 
--   to sender node at the time of sending of message
data Message = Message { 
                 val::Double
               , senderId::Int
               , sendState::V.Vector Int64
               }
 deriving (Eq,Show,Typeable,Generic)

instance Binary Message


-- | Main Logic of comparing two messages based on
--   their StateVector (refer to documentation for more details)
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
-- | auxiliary configuration type for starting process on each node
data BroadcastConfig = Config {
              initStateVec::NodeStateIM
             , bSenderId:: Int
             , bSendFor::Int
             , bSeed:: Int 
             }
 deriving (Eq,Show,Typeable,Generic)

instance Binary BroadcastConfig

type NodeStateM = MV.MVector RealWorld Int64 -- Node State Mutable version 
type NodeStateIM = V.Vector Int64  -- Node State immutable for sending in Message

-- | storeMessages inserts the coming message in the accumulated
--   list after comparision, Its guaranteed that message would 
--   reside at the corect postion
storeMessages::[Message]->Message->[Message]
storeMessages [] m = [m]
storeMessages acc@(x:xs) m = case compare m x of
  GT -> m:acc
  EQ | senderId m > senderId x -> m:acc 
  _   -> x : storeMessages xs m

-- | updateStateVecIM takes a mutable unboxed vector (here NodeStateM) and other
--   immutable unboxed vector and modifies the former with applying updateVal function
updateStateVecIM::(PrimMonad m, MV.Unbox a, Ord a)=> (MV.MVector (PrimState m) a) -> V.Vector a -> m ( )
updateStateVecIM oldStateVec newMsgStateVec = V.ifoldM'_ (updateVal) oldStateVec newMsgStateVec

-- | updateVal updates a value of mutable vector if the value supplied is larger
updateVal::(PrimMonad m, MV.Unbox a,Ord a)=>MV.MVector (PrimState m) a -> Int-> a -> m (MV.MVector (PrimState m) a)
updateVal mvector idx val = do
  oldVal <- MV.read mvector idx
  when (val > oldVal) $ MV.write mvector idx val 
  return mvector

-- | Starting process which will run on each node
--   converts the immutable nodeStateVec to mutable version
--   then spawns a thread for broadcasting messages with 
--   reference to the mutable node state vec, random number list
--   maximum sending time and receiver pids then starts 
--   the message receiving loop
startNodeProcess::BroadcastConfig->Process ()
startNodeProcess (Config nodeStateVecIM senderId sendFor seed) = do
  p <- getSelfPid
  say $ "Started process " ++ show p

  currentTime <- liftIO getCurrentTime
  let randomList = randomRs (0::Double,1::Double) (mkStdGen seed)
      sendingTime = addUTCTime (fromIntegral sendFor) currentTime
  
  nodeStateVecM <- liftIO $ V.unsafeThaw nodeStateVecIM
  pids <- expect ::Process [ProcessId]
  
  spawnLocal $ sendMsg nodeStateVecM senderId sendingTime randomList pids
  accumulateIncomingMsgs nodeStateVecM 0 [] []

-- | The accumulating process loop, It runs on each node 
--   updates the NodeState Vec, accumutales
--   messages and decide when to print the results if got
--   any signal otherwise do same operations in loop
accumulateIncomingMsgs::NodeStateM->Int->[Message]->[NodeId]->Process ()
accumulateIncomingMsgs nodeStateVec count acc nodes =
  receiveWait [
    match $ \m@(Message d sid sState::Message) -> do
      liftIO $ updateStateVecIM nodeStateVec sState
      accumulateIncomingMsgs nodeStateVec (count+1) (m:acc) nodes,
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
--   it send the head of the random number list after updating the 
--   node state vector with increase by one in index senderId 
sendMsg::NodeStateM->Int->UTCTime->[Double]->[ProcessId]->Process ()
sendMsg nodeStateVecM senderId stoppingTime rNums pids = do
  currentTime <- liftIO getCurrentTime
  if currentTime >= stoppingTime then do
       node <- getSelfNode
       let allNodeCount = length pids
       void $ spawnLocal (forM_ pids $ \p -> send p (node,allNodeCount))
      else do
           liftIO $ MV.modify nodeStateVecM  (+1) senderId 
           sState <- liftIO $ V.freeze nodeStateVecM
           let msg = Message (head rNums) senderId sState
           forM_ pids $ \p -> send p msg
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
