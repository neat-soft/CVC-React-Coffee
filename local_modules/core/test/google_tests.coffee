should = require('should')
{$p, $u, di, expect, config} = require('../index')
_ = require('lodash')

di.describeGlobal 'GoogleAPI', (ctx, it) ->
  defaultTimeout = 20000
  before (done) ->
    ctx.configure config.parseConfig('./')..., {}
    ctx.registerAll require('../src/google')
    done()

  #afterEach (done) -> done()

  describe "Authentication", ->
    beforeEach (done) -> ctx.invoke (googleApiFactory) -> done()
    it "should authenticate credentials", ->
      @timeout(defaultTimeout)
      ctx.googleApiFactory.authorize(['https://www.googleapis.com/auth/drive.readonly']).then (results) ->
        should.exist(results.access_token)
        results.token_type.should.equal("Bearer")

  describe "Drive", ->
    beforeEach (done) -> ctx.invoke (googleDriveApi) -> done()
    it "should find the TestSync folder", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFolder("TestSync").then (folder) ->
        should.exist(folder)
        folder.title.should.equal("TestSync")

    it "should list files in the test folder", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        ctx.googleDriveApi.listFiles(folderId).then (files) ->
          (files.length > 0).should.equal(true)
          ("TestReadonly" in _.map(files, (file) -> file.title)).should.equal(true)

    it "should find a specific file by full path", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFile("TestSync/TestReadonly").then (file) ->
        file.title.should.equal("TestReadonly")

    it "should delete all extra files in the test folder", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        ctx.googleDriveApi.listFiles(folderId).then (files) ->
          (_.map files, (file) ->
            unless file.title == 'TestReadonly'
              ctx.googleDriveApi.deleteFile(file.id)
          ).then ->
            $u.pause(1000).then ->
              ctx.googleDriveApi.listFiles(folderId).then (files) ->
                files.length.should.equal(1)

    it "should create a new file in a specific folder", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        ctx.googleDriveApi.createFile(folderId, "NewTest1", 'spreadsheet').then (file) ->
          file.parents[0].id.should.equal(folderId)
          should.exist(file?.id)

    it "should create a new folder and write to it", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        ctx.googleDriveApi.createFile(folderId, "SubFolder", 'folder').then (subFolder) ->
          should.exist(subFolder.id)
          ctx.googleDriveApi.findFirstFolder("TestSync/SubFolder").then (subFolderId) ->
            should.exist(subFolderId)
            subFolderId.should.equal(subFolder.id)
            ctx.googleDriveApi.createFile(subFolderId, "NewTest1", 'spreadsheet').then (file) ->
              file.parents[0].id.should.equal(subFolderId)
              should.exist(file?.id)

    it "should update modified time of a file", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        ctx.googleDriveApi.search(folderId, "NewTest1", 'spreadsheet').then (origFile) ->
          origFile = origFile[0]
          ctx.googleDriveApi.updateModifiedDate(origFile.id).then ->
            ctx.googleDriveApi.search(folderId, "NewTest1", 'spreadsheet').then (updatedFile) ->
              updatedFile = updatedFile[0]
              updatedFile.id.should.equal(origFile.id)
              updatedFile.modifiedDate.should.not.equal(origFile.id)

  describe "Spreadsheet", ->
    beforeEach (done) -> ctx.invoke (googleSpreadsheetApi, googleDriveApi) -> done()

    it "should read a file", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFile("TestSync/TestReadonly").then (file) ->
        ctx.googleSpreadsheetApi.getSheet(file.id, 'Sheet1').then (sheet) ->
          sheet.read().should.eql [
            {cola: 1, colb: 'a'}
            {cola: 2, colb: 'b'}
            {cola: 3, colb: 'c'}
            {cola: 4, colb: 'd'}
          ]

    it "should write to a file", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        data = [
          {cola: 1, colb: 'a'}
          {cola: 2, colb: 'b'}
        ]
        ctx.googleSpreadsheetApi.createSheet(folderId, "NewTestSheet").then (sheet) ->
          sheet.overwrite(['cola', 'colb'], data).then ->
            sheet.read().should.eql(data)

    it "should write to a part of a file", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        data = [
          {cola: 1, colb: 'a'}
          {cola: 2, colb: 'b'}
          {cola: 3, colb: 'c'}
          {cola: 4, colb: 'd'}
        ]
        ctx.googleSpreadsheetApi.createSheet(folderId, "NewTestSheet2").then (sheet) ->
          sheet.overwrite(['cola', 'colb'], data[0..1], 0).then ->
            sheet.overwrite(['cola', 'colb'], data[2..3], 2).then ->
              sheet.read().should.eql(data)

    it "should write past row 1000", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        data = [
          {cola: 1, colb: 'a'}
        ]
        ctx.googleSpreadsheetApi.createSheet(folderId, "NewTestSheet3").then (sheet) ->
          sheet.resize(1005, 2).then ->
            sheet.overwrite(['cola', 'colb'], data, 1001).then ->
              newData = []
              newData[1001] = data[0]
              sheet.read().should.eql(newData)

    it "should chunk writes into blocks", ->
      @timeout(defaultTimeout)
      ctx.googleDriveApi.findFirstFolder("TestSync").then (folderId) ->
        data = [
          {cola: 1, colb: 'a'}
          {cola: 2, colb: 'b'}
          {cola: 3, colb: 'c'}
          {cola: 4, colb: 'd'}
        ]
        ctx.googleSpreadsheetApi.createSheet(folderId, "NewTestSheet4").then (sheet) ->
          sheet.resize(1005, 2).then ->
            sheet.overwrite(['cola', 'colb'], data, 0, 3).then ->
                sheet.read().should.eql(data)
