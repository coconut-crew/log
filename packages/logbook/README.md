# design

problem:
we need to keep track of logs from multiple sources (server and client). ideally, we merge these logs into a single output source, which needs to then be read by the ui interface to be displayed.

subproblems:

- how do we store these logs?
- how do we receive logs from the server
  - can we generalize this so this question becomes how we receive logs from any source (server, client, other player)?
- how do we expose the logs
- how do we automatically consolidate logs from actors?
- query logs? how?
- what if logs consume too much ram :(

solutions:

1. for now we can just naively store them in a large table
2. do we do a custom unreliable layer? yes!
    3. dont generalize for now
3. there will be a single logbook.
