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
import           Data.Binary.Put
import           Data.Binary.Get
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

-- | BroadcastingGroup consists of the nodeId from
--   which messages has to be broadcated or sent to
--   the receiver processes

data BroadCastingGroup = BG Int NodeId [ProcessId]
   deriving (Eq,Show)

-- | Starting process which will run on each node
--   before message sending starts to be ready to accept
--   accumulate messages
startReceiving::Process ()
startReceiving = do
  p <- getSelfPid
  say $ "Started process " ++ show p
  accumulateIncomingMsgs 0 [] []

-- | The accumulating process, It runs on each node and
--   all other nodes send messages to them and they accumutale
--   the results and decide when to print the results if got
--   any signal.They perform only receiving task
accumulateIncomingMsgs::Int->[Double]->[NodeId]->Process ()
accumulateIncomingMsgs count acc nodes =
   receiveWait [
            match $ \(Message d sid sState::Message) ->
              accumulateIncomingMsgs (count +1) (d:acc) nodes,
            match $ \(node::NodeId,totalNodes::Int)->
              if (length.nub $ node:nodes)==totalNodes then
                  say $ unlines ["\ntotal messages : " ++ show count,
                      "sigma : " ++ (show .sum .zipWith (*) [1..] $ acc) ]
                else
                accumulateIncomingMsgs count acc (node:nodes)
              ]

-- | startSendingMsg is the process which calls sendMsg
--   with proper argument and random number list i.e
--   the time for which message sending has to be done
--   and the random number list generated by seed
startSendingMsg::(Int,Int,Int,[ProcessId]) -> Process ()
startSendingMsg (senderId,sendFor,seed,pids) = do
   currentTime <- liftIO getCurrentTime
   let randomList = randomRs (0::Double,1::Double) (mkStdGen seed)
       sendingTime = addUTCTime (fromIntegral sendFor)  currentTime
   sendMsg senderId sendingTime randomList pids

-- | sendMsg checks the current time of the node
--   and sends proper signal (in the form of different type of message)
--   to the receiving process that sending time has expired, else
--   it swapns a thread which will send the head od the random number list
--   to the receiving nodes (processes) and this cycles continues
sendMsg::Int->UTCTime->[Double]->[ProcessId]->Process ()
sendMsg senderId stoppingTime rNums pids = do
  currentTime <- liftIO getCurrentTime
  if currentTime >= stoppingTime then do
       node <- getSelfNode
       let allNodeCount = length pids
       void $ spawnLocal (forM_ pids $ \p -> send p (node,allNodeCount))
      else do
         forM_ pids $ \p -> do
           send p (Message (head rNums) senderId V.empty) 
         sendMsg senderId stoppingTime (tail rNums) pids

-- | entry in static remote table of our functions for
--   run time accese by every node
remotable ['startReceiving, 'startSendingMsg]

-- | broadcast spawns the process on the node to send messages
--   continuosly to the receiving members by calling startSendingMsg
broadCast::Int->Int->BroadCastingGroup->Process ()
broadCast sendFor seed (BG senderId n recvs) =
       void $ spawn n $ $(mkClosure 'startSendingMsg) (senderId,sendFor,seed,recvs)

-- | Given a list of NodeIds makeBroadCastGroups returns a list
--   of BroadcastingGroups
makeBroadCastGroups::[NodeId]->Process [BroadCastingGroup]
makeBroadCastGroups nodes = do
  pids <- forM nodes $ \node -> spawn node $ $(mkStaticClosure 'startReceiving)
  let bGroups = zipWith3 BG [1..] nodes (repeat pids)
  return bGroups

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
  broadCastingGroups <- makeBroadCastGroups $ mnode:slaves
  say "All Nodes Started"
  zipWithM_ (broadCast sendFor) [seed..] broadCastingGroups
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
