# CloudHaskellBeginner

This is a beginner project .. I am experimenting first time with Cloud Haskell while
the problem or project goal is more fundamental in distributed computing.

# Project Goals ::
My goal is to implement a distributed system in which:

1: several nodes form a cluster and send messages (a random number) to each other 
   such that messages from each node reaches every other node in the cluster.

2: message sending is being done for a specific amount of time and afterwards message sending stops
   now comes the so called grace period time in which nodes don't send the messages but any unreceived
   message is got received.
   Also within this time only node start to print the output which is a tuple
    (|m|,for i = 1 to |m| -> sum of {mi * i})
    where
     m is the list of all messages received by each node and ordered by sending time of node
     mi is the i'th message sent by some node or basically i'th element of m i.e. a random number (0,1)

3: after the grace period the program gets killed

#My assumptions ::
 
 * I have assumed that the underlying network is quiet rock solid for now
   so no message loss supposed at this moment.

 * None of failure cases is handled at this moment while they can be embedded
   in the current system if asked to do so.

 * Sending of copies of the same message to multiple nodes by a particular node is
   assumed to be an atomic operation for now (while in real scenarios it may have little 
   latencies depending on the physical machine and several other factors) i.e. If node A broadcasts
   a message a1 to all other nodes (Say B,C etc) then sending time of a1 at B and C
   would be same.
 
 * If Node A sends two messages m1 and m2 to Node B then B receives in order
   i.e. first m1 and then only m2 ( Guaranteed by distributed-process library).

 * There is "no" pre-assumption that clocks of all nodes agree with all.


#Solution ::

I can see inherently presence of broadcasting nature in the problem

So I was trying to build an infrastructure using which every node 
can broadcast its message to all others

Now after I built the infrastructure for braodcasting messages 
it was simple to turn off the nodes and stop after a specified 
amount of time, which also I have immplemented, it was just a 
matter of time to grasp the library (distributed-process)  CH.


#Difficulties ::
Now problem I faced when I have to print the results, which requires arranging 
the messages in the order of sending time which is a fundamental problem in any
distributed programming.

I came up with a solution of estimating the clock difference time with first 
introducing a rondom offset to the local clocktime of nodes and then estimating
round-trip time between all pairs of node, this would have given me an estimate of
the relative clock differences between the nodes.

But after a little more research and thinking I came upto the point that it will not 
give us the exactness required of the scale we may want to guarantee in distributive 
programing (we may differ in sec's scale which is quiet big from computing's point of view) 

#My Algorithm ::

After analysing the difficulties I came upto the point that we can't rely on any
estimation technique as we may want guarantee that the output should be
accurate while it may not be the case with estimation techniques (NTP etc).

Then I focussed on the point that what information we can use to compare the messages
which is proofed or guaranteed and finally came to my current solution to
this fundamental problem in distributed systems but restricted to our given use case.
 
#Specifications about the Algorithm

 * Every node maintains the best possible known state of the global known system.

 * For now state is encoded as a Integer Vector of length of total number of 
   nodes present in the cluster.

   Let V represents a State Vector of any node K,
               V [i] = e
               |V| = total number of nodes in the system

   Here element e of vector V at index i represents that it is known in the 
   graph or the system that node number "i" has sent message number "e" i.e 
   upto e [1..e].

 * The Guarantee of the state info i.e. State Vector present in the message 
   is in relation or in context with the sending time of that message of the
   sender node.

   There is "NO" guarantee that even at the receiving time the state of the
   sender node remains the same , But it is a proof that at the time of sending
   of that message it was so, according to the sending node.

 * While sending of any message, the node inserts the best known state info
   into the message so that the information can be guaranteed and propagated
   to the receiving nodes. In this information flow happen in the system.

 * Whenever a node receives a message it compares the state info present in
   the message and it's own state info and then modifies its info or state 
   if it gets new news so that it will send new info while sending of message.
   
 * Mechanism for comparision of messages State and Node State and updation: 

     message's state vec Vs
     node's state vec Ns

     for all i == 0 to |Ns|:: 
        
        if Vs [i] > Ns [i]
          then 
            Ns [i] = Vs [i]
 
 * Whenever a node receives a message then it inserts the message in the correct 
   index by doing comparision on the basis of message state info.

 * for comparing any two message m1 and m2 of senderId X and Y say with state vectors 
   VsX and VsY, we can compare only resepective indices X and Y of both the vectors
   from this we can draw conclusions ... or guarantees while we can't say anything
   with numbers present in other indices.

   for e.g. say VsX [X] = VsY [X]
     this tells us while sending of the message m2 from Y it was known that X has 
     sent upto message number (VsY [X]) so we can guarantee that m2 has been sent
     later than m1 as m2 was sent sometime when Y know that X has sent m1
   
   In a similar way we can draw conclusions for other finite cases which I have
   coded in the solution (Ord Instance of Message type)

 * There is one case when ( VsX [X] > VsY [X] ) && ( VsX [Y] < VsY [Y]) in this 
   particular case we can't say anything or guarantee any thing about the sending
   time order as we don't have enough information and these messages are treated to 
   be concurrent or in comparision equal.

   Consider a scenario where there are 3 nodes A,B,C and nodes A and B sends the 
   first message to C (m1 and m2). At this time we can't say anything about order
   of the message sending time of m1 and m2.

   For this type of messages best possible treatment would have been using an
   estimation technique like guessing clock skews or with NTP to order them
   but for now I have used an arbitrary rule to order these messages based on
   their sender Id . I have made this rule consistent throughout whole system
   so this will not hamper correctness much as long as all nodes follow this.
 
 * So finally I got an ordering without the use of the clock.

 * That's all after getting final signal from other nodes each nodes start computing
   and printing the result to stderr and then shuts down on time.

#For Better or Higher Score ::

I came up  with a simple hack of generating the random number list and then 
dividing the list into chunks and giving the sorted chunks to the worker process
to send across ... hoping this will increase the sigma :)
 using the fact that
  1*5 + 2*6 + 3*7 > 1*7 +2*6 + 3*5 
 
 But I have not implemented that as I thought this must not be the concern of the test
 interesting part might be implementation of virtual clock as learning to handle APIs
 is not a big thing in my view.

#About the code ::

I have kept my code very simple and understandable I know it is not a polished Haskell 
Program but I gave more importance to design and implement the algorithm with correctness.

I also know code is full of flaws and optimisation oppurtunities are being ignored.



Thanks a lot for this nice problem I enjoyed the journey to solve it :)

