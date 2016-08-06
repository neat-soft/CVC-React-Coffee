_ = require("lodash")
path = require('path')

module.exports = (grunt) ->
  grunt.config.set("dockerRoot", "./")
  grunt.loadTasks('local_modules/core/grunt-tasks');
  grunt.loadNpmTasks('grunt-contrib-watch');
  grunt.loadNpmTasks('grunt-browserify');

  grunt.config.merge
    watch:
      core:
        files: 'local_modules/core/src/**/*.coffee',
        tasks: [ 'shell:compile-core' ]

      'react-canvas':
        files: 'local_modules/react-canvas/lib/**/*.js',
        tasks: [ 'compile:clientjs' ]

      src:
        files: ['src/**/*.coffee']
        options:
          spawn: false
          event: ['all']

      clientjs:
        files: ['src/client/**/*.coffee', 'src/components/**/*.coffee', 'src/locale/**/*.coffee']
        options:
          spawn: false
          event: ['all']

    shell:
      'compile-core':
        command: -> "coffee -o local_modules/core/lib --compile --map local_modules/core/src"
      'compile':
        command: -> "coffee -o lib --compile --map src"
      'clean':
        command: -> "rm -rf public/assets public/bundled_assets lib/*"
      'coffee':
        command: (src, dest) -> "coffee -o #{dest} -c --map #{src}"

  clientjsDeps = {}
  grunt.event.on 'watch', (action, filepath, target) ->
    if target == 'src'
      relativePath = path.relative("src/", filepath).replace(/coffee$/,'js')
      dest = path.dirname(path.join('lib/', relativePath))
      grunt.task.run "shell:coffee:#{filepath}:#{dest}"
    else if target == 'clientjs'
      if _.keys(clientjsDeps).length == 0
        return grunt.task.run "compile:clientjs"
      relativePath = path.relative("src/", filepath).replace(/coffee$/,'js')
      libFile = path.join('lib/', relativePath)
      _.each clientjsDeps, (deps, rootScript) ->
        if libFile in deps
          grunt.task.run "compile:clientjs:file:#{rootScript}"

  compileClient = (file, cb) ->
    browserify = require('browserify')
    b = browserify();
    opts =
      detectGlobals: false
    unless file.match(/.*\/common_libs.js$/)?
      opts.bundleExternal = false
    b.reset(opts)
    if file.match(/.*\/common_libs.js$/)?
      b.require('react')
      b.require('react-canvas')
      b.require('lodash')
      b.require('events')
      b.require('moment')
    b.add(file);
    buffers = []
    out = b.bundle()
    out.on 'data', (chunk) -> buffers.push(chunk)
    relativePath = path.relative("lib/client", file)
    out.on 'end', ->
      code = Buffer.concat(buffers).toString()
      cwd = process.cwd()
      deps = _.map (b?._mdeps?.visited || []), (visited, fileName) ->
        path.relative(cwd, fileName) if visited
      deps = _.reject deps, (dep) -> dep.match(/^node_modules.*/)?
      clientjsDeps[file] = deps
      grunt.file.write(path.join("public/assets/js/client/",relativePath), code)
      cb()

  grunt.registerTask 'compile:clientjs', () ->
    clients = grunt.file.expand("lib/client/**/*.js")
    grunt.task.run _.map clients, (client) -> "compile:clientjs:file:#{client}"

  grunt.registerTask 'compile:clientjs:file', (file) ->
    done = @async()
    compileClient(file, done)

  grunt.registerTask 'coffee:file', (file) ->
    done = @async()

  grunt.registerTask 'clean', ['shell:clean']
  grunt.registerTask 'compile', ['shell:compile-core','shell:compile','compile:clientjs']
  grunt.registerTask 'dev', ['clean', 'compile', 'watch']
  grunt.registerTask 'dist', ['clean','compile']