{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
module Main where
import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node                   (initRemoteTable)
import           Control.Monad
import           Data.Binary
import           Data.List                                          (nub)
import           Data.Time.Clock
import           Data.Typeable
import           GHC.Generics                                       (Generic)
import           System.Environment                                 (getArgs)
import           System.Random
import           Text.Printf

data BroadCastingGroup = BG NodeId [ProcessId]
   deriving (Eq,Show)

start::Process ()
start = do
  p <- getSelfPid
  say $ "Started process " ++ show p
  accumulateIncomingMsgs 0 [] []

accumulateIncomingMsgs::Int->[Double]->[NodeId]->Process ()
accumulateIncomingMsgs count acc nodes =
   receiveWait [
            match $ \(i::Double) ->
              accumulateIncomingMsgs (count +1) (i:acc) nodes,
            match $ \(node::NodeId,totalNodes::Int)->do
              if (length.nub $ node:nodes)==totalNodes then do
                  say $ unlines ["\ntotal messages : " ++ show count,
                      "sigma : " ++ (show .sum .zipWith (*) [1..] $ acc) ]
                  getSelfNode >>= terminateSlave
                else do
                liftIO . putStrLn $ "got node signal " ++ (show (node,totalNodes))
                accumulateIncomingMsgs count acc (node:nodes)
              ]

sendMsg::(Int,Int,[ProcessId]) -> Process ()
sendMsg (sendFor,seed,pids) = do
   currentTime <- liftIO getCurrentTime
   let randomList = randomRs (0::Double,1::Double) (mkStdGen seed)
       sendingTime = addUTCTime (fromIntegral sendFor)  currentTime
   sendRandoms sendingTime randomList pids

sendRandoms::UTCTime->[Double]->[ProcessId]->Process ()
sendRandoms stoppingTime rNums pids = do
  currentTime <- liftIO getCurrentTime
  if currentTime >= stoppingTime then do
       node <- getSelfNode
       let allNodeCount = length pids
       spawnLocal (forM_ pids $ \p -> send p (node,allNodeCount))
       say "Time Up! For Sending Msg"
      else do
         spawnLocal (forM_ pids $ \p -> send p (head rNums))
         sendRandoms stoppingTime (tail rNums) pids

remotable ['start, 'sendMsg]

broadCast::Int->Int->BroadCastingGroup->Process ()
broadCast sendFor seed (BG n recvs) = do
       liftIO . putStrLn .show $ (BG n recvs)
       void $ spawn n $ $(mkClosure 'sendMsg) (sendFor,seed,recvs)

makeBroadCastGroups::[NodeId]->Process [BroadCastingGroup]
makeBroadCastGroups nodes = do
  pids <- forM nodes $ \node -> spawn node $ $(mkStaticClosure 'start)
  let bGroups = zipWith BG nodes (repeat pids)
  return bGroups


myRemoteTable :: RemoteTable
myRemoteTable = Main.__remoteTable initRemoteTable

master :: Backend -> [NodeId] -> Process ()
master backend slaves = do
  liftIO . putStrLn $ "Slaves: " ++ show slaves
  mnode<-getSelfNode
  bGroups <- makeBroadCastGroups $ mnode:slaves
  forM_ bGroups $ broadCast 1 1
  liftIO $ threadDelay 2000000

main :: IO ()
main = do
  args <- getArgs

  case args of
    ["master", host, port] -> do
      backend <- initializeBackend host port myRemoteTable
      startMaster backend (master backend)
    ["slave", host, port] -> do
      backend <- initializeBackend host port myRemoteTable
      startSlave backend
