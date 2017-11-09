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
import           Data.Typeable
import           GHC.Generics                                       (Generic)
import           System.Environment                                 (getArgs)
import           Text.Printf

data BroadCastingGroup = BG NodeId [ProcessId]
   deriving (Eq,Show)

start::Process ()
start = do
  p <- getSelfPid
  say $ "Started process " ++ show p
  loop

loop::Process ()
loop = do
  p <- getSelfPid
  liftIO . putStrLn $ show p ++ " waiting for msg "
  receiveWait [match $ \(i::Int) -> liftIO .putStrLn $ "got this : " ++ show i,
              match $ \(p::ProcessId)-> send p $ "replying Back to "++ show p]
  loop

sendMsg::(Int,ProcessId) -> Process ()
sendMsg (msg,pid) = do
   send pid msg

sendAgain::ProcessId -> Process ()
sendAgain pid = do
  liftIO . putStrLn $ "write msg to send ::"
  msg <- liftIO getLine
  send pid msg


remotable ['sendAgain, 'start, 'sendMsg, 'loop]

u=undefined

broadCast::Int->BroadCastingGroup->Process ()
broadCast msg (BG n recvs) = do
  forM_ recvs $ \r->do
     spawn n $ $(mkClosure 'sendMsg) (msg,r)
     pid <- getSelfPid
    -- n <-getSelfNode
     liftIO.putStrLn $ show pid
    -- liftIO.putStrLn $ show n

makeBroadCastGroups::[NodeId]->Process [BroadCastingGroup]
makeBroadCastGroups nodes = do
  pids <- forM nodes $ \node -> spawn node $ $(mkStaticClosure 'start)
  let bGroups = zipWith BG nodes $ zipWith (\p ps -> (filter (/=p) ps)) pids (repeat pids)
  return bGroups


myRemoteTable :: RemoteTable
myRemoteTable = Main.__remoteTable initRemoteTable

master :: Backend -> [NodeId] -> Process ()
master backend slaves = do
  liftIO . putStrLn $ "Slave: " ++ show slaves
  mnode<-getSelfNode
  bGroups <- makeBroadCastGroups $ mnode:slaves
  forM_ bGroups $ broadCast (1111::Int)

  liftIO $ threadDelay 2000000

  -- Terminate the slaves when the master terminates (this is optional)
  --terminateAllSlaves backend

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
