# Specification-based testing of QUIC implementations with Ivy

This demo demonstrates specification-based testing of QUIC implementations with
[Ivy](https://github.com/kenmcmil/ivy/), as described in the two following papers:
* McMillan, Kenneth L., and Lenore D. Zuck. ["Formal specification and testing
  of QUIC."](http://mcmil.net/pubs/SIGCOMM19.pdf) Proceedings of the ACM
  Special Interest Group on Data Communication. 2019.
* McMillan, Kenneth L., and Lenore D. Zuck. ["Compositional Testing of Internet
  Protocols."](http://www.mcmil.net/pubs/SECDEV19.pdf) 2019 IEEE
  Cybersecurity Development (SecDev). IEEE, 2019.

You will find the Ivy QUIC specification in the `quic23` branch of the Ivy
repository, under `doc/examples/quic`. Follow [this
link](https://github.com/kenmcmil/ivy/tree/2d55399e887f489423bf2e896f00dc48b8e23ef0/doc/examples/quic)
for the exact version used in this demo.

This demo should run on most systems with a POSIX shell. Please note that this
is not a polished product, but a quick attempt at replicating some of the
results of McMillan and Zuck. Please see the blog post at TODO for context.

# Acknowledging ACK-only packets

The QUIC specification states that, roughly, a packet is ack-eliciting if it
contains a frame other than an ack frame, and that no packet should acknowledge
_only_ packets that are not ack-eliciting. We will call this the ACK-Eliciting
Rule. So, it is a violation of the ACK-Eliciting Rule to send a packet P that
acknowledges only packet Q, where Q contains only an ACK frame. When this
requirement is violated, we run the risk of entering an infinite loop between
two parties that keep acknowledging each other's acknowledgments.

For this demo, we initially planned on modifying Picoquic to make it violate
the ACK-eliciting rule, and then see if Ivy would catch it. However, we
discovered through the process that, even without modifying Picoquic to plant
the bug, Picoquic already violates the rule.

To catch violations of the ACK-Eliciting Rule, we added some requirements in
the Ivy QUIC specification (the specification did not stipulate this
requirement). See the patched `.ivy` files in `./resources/ack-patch.diff`.

Note that we are using an [old version of Picoquic](https://github.com/private-octopus/picoquic/tree/4c061c0b24e35282108d8c57eef41939a692a6c4). This is because the Ivy QUIC
specification follows IETF draft revision 23 (which is outdated), and thus we
chose a version of Picoquic that was developed against draft 23.

# Demo scenario

We use `quic_server_test_stream.ivy`, which a test scenario in which Ivy
simulates a client that downloads a single file over HTTP from the QUIC server
under test. Ivy randomly exercises protocol steps around this core scenario in
order to produce a wide variety of client-server interactions.

# Running the demo and inspecting the results

To run the demo, use `./run.sh`. This will build a Docker image with all the
needed artifacts and then run 10 randomized tests in a Docker container. Note
that building the initial image can take a long time, but subsequent runs will
not have to rebuild it.

For each test run, Ivy prints a short summary, including the line in the
specification of the assertion that failed, if any.

Because the tests are randomized, only some runs may produce the issue in
Picoquic that we want to exhibit. The issue manifests by the failure of the
assertion at line `492` in `quic_frame.ivy`. If a run exhibits the issue, e.g.
run `0`, you should see the following output.

```
../quic_server_test_stream (0) ...
implementation command: ['./picoquicdemo', '-L', '-l', '-']
server pid: 42
timeout 100 ./build/quic_server_test_stream seed=436 the_cid=12 server_cid=13 client_port=4999 client_port_alt=5000
quic_frame.ivy: line 492: error: assumption failed
client return code: 1
FAIL
```

Note that some test runs terminate with `Ran out of values for type cid`. This
is an error produced internally by the Ivy tester, and it does not indicate an
issue with the picoquic server. Such runs should be discarded. Since the
testing procedure still produces useful results in other runs, we have not
investigated the cause of the error.

After all the tests complete, you should find the results in `./results/`. The
test results for run number `N` consists of three files with extension
`quic_server_test_streamN.iev`, `quic_server_test_streamN.err`, and
`quic_server_test_streamN.out`.
* `quic_server_test_streamN.iev` contains a trace of specification events
* `quic_server_test_streamN.out` contains the trace output that Picoquic printed on `stdout`
* `quic_server_test_streamN.err` contains the output that Picoquic printed on `stderr`

An example of test results appears in `./example_results/`. In
`./example_results/quic_server_test_stream0.out`, we can see at lines 65 to 69
that the server sends a handshake packet with an ACK frame that acknowledges
a handshake packet with sequence number 2.

```
65  Sending packet type: 4 (handshake), S0, Version ff000017,
66      <0000000000000000>, <7ffd5d1c33500ed3>, Seq: 2, pl: 1022
67      Prepared 1002 bytes
68      Crypto HS frame, offset 0, length 993: 0800006e006c0000...
69      ACK (nb=0), 2
```

However, we can see at lines 57 to 61 that the handshake packet with sequence
number 2 (sent by the client) has a decrypted payload consisting of an ACK
frame and some padding. Thus, handshake packet 2 is not an ACK-eliciting packet
and should not be acknowledged on its own.

```
57  eceiving packet type: 4 (handshake), S0, Version ff000017,
58     <7ffd5d1c33500ed3>, <0000000000000000>, Seq: 2, pl: 41
59     Decrypted 21 bytes
60     ACK (nb=0), 1
61     padding, 16 bytes
```

In the Ivy trace, the problematic server packet appears at line 31, why the
non-ACK-eliciting packet from the client appears at line 23.

Note that we observed the problematic behavior only in scenarios in which the
server retransmits an already-sent packet and a non-ACK-eliciting packet is
pending acknowledgment. We presume (although we have not checked)
that this is an issue affecting a code path used only during retransmission. If
our presumption is correct, this problem would not have been detected without
the client withholding an ACK (which causes the server to retransmit) and
sending a new, non-ACK-eliciting packet at the same time. Whether an integration
test could have produced this behavior is up for debate.
