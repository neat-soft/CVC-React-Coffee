_ = require('lodash')
throttle = require('./throttle')

exports.GoogleApiFactory = ($options, $p, $logger) ->
  googleapis = require('googleapis')

  jwt = new googleapis.auth.JWT()
  initialAuth =  $p.wrap(jwt.fromJSON $options.auth, $p.ecb())
  defaultCacheTimeout = 1000*60*60
  cachedReference = (timeout, block) ->
    ref = null
    return ->
      return $p.resolved(ref) if ref?
      $p.when(block()).then (newRef) ->
        setTimeout (-> ref = null), timeout
        ref = newRef
  return self = {
    authorize: (scope)->
      initialAuth.then ->
        scopedJwt = jwt.createScoped(scope)
        $p.wrap(scopedJwt.authorize $p.ecb()).then (result) ->
          $logger.info "AUTHORIZING FOR SCOPE [#{scope}]"
          result.scopedJwt = scopedJwt
          result

    drive: ->
      cachedReference defaultCacheTimeout, ->
        self.authorize(['https://www.googleapis.com/auth/drive.readonly', 'https://www.googleapis.com/auth/drive.file']).then (result) ->
          $logger.info "CONNECTED TO GOOGLE DRIVE"
          googleapis.drive({ version: 'v2', auth: result.scopedJwt })

    spreadsheet: ->
      spreadsheet = require('edit-google-spreadsheet');
      cachedAuth = cachedReference defaultCacheTimeout, ->
        self.authorize(['https://spreadsheets.google.com/feeds']).then (result) ->
          $logger.info "CONNECTED TO GOOGLE SHEETS"
          result

      return {
        load: (spreadsheetId, worksheetName) ->
          cachedAuth().then (auth) ->
            $p.wrap(spreadsheet.load({
              spreadsheetId: spreadsheetId
              worksheetName: worksheetName
              accessToken:
                type: 'Bearer'
                token: auth.access_token
            }, $p.ecb()))
      }
  }

exports.GoogleDriveApi = ($p, googleApiFactory) ->
  mimeTypes = {
    folder: 'application/vnd.google-apps.folder'
    spreadsheet: 'application/vnd.google-apps.spreadsheet'
  }
  driveRef = googleApiFactory.drive()
  return self = {
    search: (folderId, title, type) ->
      query = "title='#{title}'"
      query+= " and '#{folderId}' in parents" if folderId?
      query+= " and mimeType = '#{mimeTypes[type]}'" if type?
      driveRef().then (drive) ->
        $p.wrap(drive.files.list({q: query}, $p.ecb())).then (result) ->
          _.flatten([result.items])

    findFolder: (path, parent) ->
      path = path.split('/')
      $p.create (p) ->
        currentParent = parent
        nest = ->
          folder = path.shift()
          self.search(currentParent, folder, 'folder').then (items) ->
            return p.error("Folder [#{folder}] must be unique!") if items.length > 1
            return p.resolve() if items.length == 0
            return p.resolve(items[0]) if path.length == 0
            currentParent = items[0].id
            nest()
        null
        nest()

    findFirstFolder: (path, parent) ->
      self.findFolder(path, parent).then (folder) -> folder?.id

    findFirstFile: (path) ->
      path = path.split('/')
      fileName = path.pop()
      self.findFirstFolder(path.join('/')).then (folderId) ->
        self.search(folderId, fileName).then (files) -> files[0]

    listFiles: (folderId) ->
      query = {}
      query = {q: "'#{folderId}' in parents"} if folderId?
      driveRef().then (drive) ->
        $p.wrap(drive.files.list(query, $p.ecb())).then (result) ->
          _.flatten([result.items])

    exists: (folderId, title, type) ->
      self.search(folderId, title, type).then (existingFiles) -> existingFiles.length > 0

    createFile: (folderId, title, type) ->
      self.exists(folderId, title, type).then (exists) ->
        return $p.error("Already exists") if exists
        driveRef().then (drive) ->
          $p.wrap(drive.files.insert({
            resource: {
              title: title
              mimeType: mimeTypes[type]
              parents: [{ kind: 'drive#parentReference', id: folderId}]
            }
          }, $p.ecb()))

    deleteFile: (fileId) ->
      driveRef().then (drive) ->
        $p.wrap(drive.files.delete({fileId: fileId}, $p.ecb()))

    updateModifiedDate: (fileId) ->
      driveRef().then (drive) ->
        $p.wrap(drive.files.touch({fileId: fileId}, $p.ecb()))
  }

exports.GoogleSpreadsheetApi = ($p, $u, googleApiFactory, googleDriveApi) ->
  spreadsheetApi = googleApiFactory.spreadsheet()
  return self = {
    createSheet: (folderId, sheetName) ->
      googleDriveApi.createFile(folderId, sheetName, 'spreadsheet').then (file) ->
        self.getSheet(file.id, 'Sheet1')

    getSheet: (spreadsheetId, worksheetName) ->
      spreadsheetApi.load(spreadsheetId, worksheetName).then (sheet) ->
        read: ->
          convertRow = (columns, row) ->
            newRow = {}
            for own k, v of row
              newRow[columns[k]||k]=v
            newRow
          $p.wrap(sheet.receive {useCellTextValues: true}, $p.ecb()).then (rows, info) ->
            columnRow = rows['1']
            columnRow[k] = v for k, v of columnRow
            delete rows['1']
            matrix = []
            for own k, v of rows
              matrix[parseInt(k)-2] = convertRow(columnRow, v)
            matrix

        resize: (rows, columns) ->
          $p.wrap(sheet.metadata({
            title: worksheetName
            rowCount: rows
            colCount: columns
          }, $p.ecb())).then ->

        overwrite: (headers, data, rowOffset = 0, chunkSize = 500) ->
          th = throttle(1)
          updates = {}
          updates[1] = {}
          _.each headers, (header, ci) ->
            updates[1][ci+1] = header
          rowOffset+=2
          chunks = $u.chunkArray(data, chunkSize)
          (_.map chunks, (chunk, chunkIndex) ->
            th ->
              _.each chunk, (row, ri) ->
                updates[rowOffset+ri+chunkSize*chunkIndex] = {}
                _.each headers, (header, ci) ->
                  updates[rowOffset+ri+chunkSize*chunkIndex][ci+1] = row[header]
              sheet.add(updates)
              $p.wrap(sheet.send($p.ecb())).then ->
                updates = {}
          ).then ->
    }
