should = require('should')
exports.genericQueueTests = (it, queueProviderRetriever) ->
  it "should enqueue and dequeue an element", ->
    queueProviderRetriever().enqueue("TEST", "MSG1").then (ref) ->
      should.exist(ref)
      queueProviderRetriever().dequeue("TEST", 15).should.eql([ref, "MSG1"])

  it "should enqueue and dequeue objects", ->
    queueProviderRetriever().enqueue("TEST", {item:"MSG1"}).then (ref) ->
      should.exist(ref)
      queueProviderRetriever().dequeue("TEST", 15).should.eql([ref, {item:"MSG1"}])

  it "should support blocking dequeue", ->
    result = queueProviderRetriever().dequeue("TEST", 15, 2)
    queueProviderRetriever().enqueue("TEST", "MSG1").then (ref) ->
      result.should.eql([ref, "MSG1"])

  it "should support dequeueing empty queue", ->
    queueProviderRetriever().dequeue("TEST", 15).should.eql([null, null])

  it "should return size of the queue", ->
    (queueProviderRetriever().enqueue("TEST", "MSG#{i}") for i in [1..3]).then ->
      queueProviderRetriever().getSize("TEST").should.equal(3)

  it "should list all messages", ->
    (queueProviderRetriever().enqueue("TEST", "MSG#{i}") for i in [1..3]).then ->
      queueProviderRetriever().listAllMessages("TEST").then (messages) ->
        messages.sort()
        messages.should.eql("MSG#{i}" for i in [1..3])

  it "should remove message by reference", ->
    queueProviderRetriever().enqueue("TEST", "MSG1").then (ref) ->
      queueProviderRetriever().getSize("TEST").should.equal(1).then ->
        queueProviderRetriever().remove("TEST", ref).then ->
          queueProviderRetriever().getSize("TEST").should.equal(0)

  it "should suppot isEnqueued", ->
    queueProviderRetriever().isEnqueued("TEST","NONE").should.equal(false).then ->
      queueProviderRetriever().enqueue("TEST", "MSG1").then (ref) ->
        queueProviderRetriever().isEnqueued("TEST",ref).should.equal(true)

  it "should support getDelay method", ->
    queueProviderRetriever().getDelay("TEST","NONE").should.not.exist().then ->
      queueProviderRetriever().enqueue("TEST", "MSG1").then (ref) ->
        queueProviderRetriever().getDelay("TEST",ref).should.equal(0).then ->
          queueProviderRetriever().dequeue("TEST", 15).then ->
            queueProviderRetriever().getDelay("TEST",ref).then (delay) ->
              Math.round(delay).should.equal(15)

  it "should allow blocking clients to receive requeued messages", ->
    [ queueProviderRetriever().dequeue("TEST", 1, 3).should.eql(["b21db0eb84aacc91a7b30a03ad11822d", "MSG1"])
      queueProviderRetriever().dequeue("TEST", 1, 3).should.eql(["b21db0eb84aacc91a7b30a03ad11822d", "MSG1"])
      queueProviderRetriever().enqueue("TEST", "MSG1")
    ].merge()

  it "should move items back to pending status after the requested delay and increment retries", ->
    queueProviderRetriever().enqueue("TEST", "MSG1").then (ref1) ->
      queueProviderRetriever().getDelay("TEST",ref1).should.equal(0).then ->
        queueProviderRetriever().getRetryCount("TEST", ref1).should.equal(0).then ->
          queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
            queueProviderRetriever().dequeue("TEST", 15).should.eql([null, null]).then ->
              queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
                queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
                  queueProviderRetriever().getRetryCount("TEST", ref1).should.equal(1)

  it "after 5 failures should requeue the message in the dead q", ->
    queueProviderRetriever().enqueue("TEST", "MSG1").then (ref1) ->
      queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
        queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
          queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
            queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
              queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
                queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
                  queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
                    queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
                      queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
                        queueProviderRetriever().dequeue("TEST", 15).should.eql([ref1, "MSG1"]).then ->
                          queueProviderRetriever().getRetryCount("TEST", ref1).should.equal(5).then ->
                            queueProviderRetriever().setDelay("TEST", ref1, 0).then ->
                              queueProviderRetriever().dequeue("TEST", 15).should.eql([null, null]).then ->
                                queueProviderRetriever().getSize("TEST").should.equal(0).then ->
                                  queueProviderRetriever().dequeue("TEST:dead", 15).then (ref, message) ->
                                    message.should.equal("MSG1")

  it "should support getQueueSizes", ->
    [ queueProviderRetriever().enqueue("TEST", "MSG1")
      queueProviderRetriever().enqueue("TEST", "MSG2")
      queueProviderRetriever().enqueue("TEST", "MSG3")
    ].then ->
      queueProviderRetriever().getQueueSizes().then (sizes) ->
        sizes.TEST.should.equal(3)
