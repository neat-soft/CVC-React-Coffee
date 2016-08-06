should = require('should')
inline = require("../src/inline")

tests = [{
  src:  """
      <html>
        <head>
          <style>
            h1 {
              font-size: 24px;
            }
          </style>
        </head>
        <body>
          <h1>Hello World</h1>
        </body>
      </html>
    """
  result: """
      <html>
        <head>

        </head>
        <body>
          <h1 style="font-size: 24px;">Hello World</h1>
        </body>
      </html>
    """
  }
]
noSpace = (str) -> str.replace(/[ ]*/g,'')
describe "inline", ->
  it "should inline <style> tags into style attributes", (done) ->
    inline tests[0].src, (err, result) ->
      should.not.exist(err)
      noSpace(result).should.equal(noSpace(tests[0].result))
      done()