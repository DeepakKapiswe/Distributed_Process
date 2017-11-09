{-# LANGUAGE DeriveAnyClass            #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
module Main where
import           Control.Concurrent                                 (threadDelay)
import           Control.Distributed.Process
import           Control.Distributed.Process.Backend.SimpleLocalnet
import           Control.Distributed.Process.Closure
import           Control.Distributed.Process.Node                   (initRemoteTable)
import           Control.Monad
import           Data.Binary
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
  loop

loop::Process ()
loop = forever $ receiveWait [match $ \(i::Double) -> liftIO .putStrLn $ "got this : " ++ show i,
                 match $ \(p::ProcessId)-> send p $ "replying Back to "++ show p]

sendMsg::(Int,Int,[ProcessId]) -> Process ()
sendMsg (sendFor,seed,pids) = do
   currentTime <- liftIO getCurrentTime
   let randomList = randomRs (0::Double,1::Double) (mkStdGen seed)
       sendingTime = addUTCTime (fromIntegral sendFor)  currentTime
   sendRandoms sendingTime randomList pids

sendRandoms::UTCTime->[Double]->[ProcessId]->Process ()
sendRandoms stoppingTime rNums pids = do
  currentTime <- liftIO getCurrentTime
  if currentTime >= stoppingTime then
     say "Time Up! For Sending Msg"
      else do
         spawnLocal (forM_ pids $ \p -> send p (head rNums))
         sendRandoms stoppingTime (tail rNums) pids

remotable ['start, 'sendMsg]

u=undefined

broadCast::Int->Int->BroadCastingGroup->Process ()
broadCast sendFor seed (BG n recvs) = void $ spawn n $ $(mkClosure 'sendMsg) (sendFor,seed,recvs)

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
