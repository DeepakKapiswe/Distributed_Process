#!/bin/bash
stack build

stack exec example slave localhost 7775 &
stack exec example slave localhost 7776 &
stack exec example slave localhost 7777 &
stack exec example slave localhost 7778 &

stack exec example master localhost 8800 -- --send-for 5 --wait-for 4 --with-seed 3
