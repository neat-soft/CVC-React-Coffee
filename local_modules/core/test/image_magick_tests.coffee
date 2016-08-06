should = require("should")
im = require("../src/image_magick")

describe "ImageMagick", ->
  describe "Identify", ->
    it "should identify gif", (done) ->
      im.identify("test/resources/img.gif").then (info) ->
        should.exist(info, "Missing info object")
        info.should.eql {type:"GIF", dimensions: {w:10, h:20}}
        done()
    it "should identify jpeg", (done) ->
      im.identify("test/resources/img.jpg").then (info) ->
        should.exist(info, "Missing info object")
        info.should.eql {type:"JPEG", dimensions: {w:318, h:74}}
        done()

    it "should identify png", (done) ->
      im.identify("test/resources/img.png").then (info) ->
        should.exist(info, "Missing info object")
        info.should.eql {type:"PNG", dimensions: {w:32, h:30}}
        done()

    it "should reject unknown types", (done) ->
      im.identify("test/resources/img.fail").then
        success: -> should.fail("success should not be called")
        error: (err) ->
          err.should.not.equal("")
          done()

  describe "Normalize", ->
    it "should normalize gif to jpeg", (done) ->
      im.identify("test/resources/img.gif").then (infoOrig) ->
        proc = im.normalize("test/resources/img.gif", "JPEG")
        [im.identify(proc.stdout), proc].then (infoConvert) ->
          infoOrig.type="JPEG"
          infoConvert.should.eql infoOrig
          done()

    it "should normalize png to jpeg", (done) ->
      im.identify("test/resources/img.png").then (infoOrig) ->
        proc = im.normalize("test/resources/img.png", "JPEG")
        [im.identify(proc.stdout), proc].then (infoConvert) ->
          infoOrig.type="JPEG"
          infoConvert.should.eql infoOrig
          done()

    it "should fail to normalize non images", (done) ->
      im.normalize("test/resources/img.fail", "JPEG").then
        success: -> should.fail("success should not be called")
        error: (err) ->
          should.exist(err,"MISSING ERROR MESSAGE")
          err.toString().substr(0,23).should.equal("FAILED TO CONVERT IMAGE")
          done()

  describe "Resize", ->
    it "should resize and pad image to specific dimensions", (done) ->
      im.resize("test/resources/img.png", 300, 400, "PNG").then (buf) ->
        im.identify(buf).should.eql({type: 'PNG', dimensions: {w: 300, h: 400}}).then ->
          done()

    it "should return an error if invalid width is provided", (done) ->
      im.resize("test/resources/img.png", "w", 400, "PNG").should.eql(error: ["Invalid width"]).then -> done()

    it "should return an error if invalid width is provided", (done) ->
      im.resize("test/resources/img.png", 300, "y", "PNG").should.eql(error: ["Invalid height"]).then -> done()

    it "should return an error if invalid format is provided", (done) ->
      im.resize("test/resources/img.png", 300, 400, "FORMAT").should.eql(error: ["Invalid format must be one of [JPEG,PNG]"]).then -> done()
