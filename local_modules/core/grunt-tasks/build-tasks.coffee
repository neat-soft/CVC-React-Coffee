_ = require("lodash")
fs = require('fs')
spawn = require('child_process').spawn
{EventEmitter} = require('events')

parseArguments = (func) ->
  ARGS = /^function\s*[^\(]*\(\s*([^\)]*)\)/m;
  ARG_SPLIT = /,/;
  ARG = /^\s*(_?)(\S+?)\1\s*$/;
  STRIP_COMMENTS = /((\/\/.*$)|(\/\*[\s\S]*?\*\/))/mg;
  throw new Error("Unable to parse arguments for non functions") unless _.isFunction(func)
  argNames = [];
  funcText = func.toString().replace(STRIP_COMMENTS, '');
  argMatches = funcText.match(ARGS);
  _.each argMatches[1].split(ARG_SPLIT), (arg) ->
    arg.replace ARG, (all, underscore, name) ->
      argNames.push(name);

  return argNames;

module.exports = (grunt) ->
  dockerRoot = grunt.config.get('dockerRoot')
  dockerRoot?="deploy"

  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')
    shell:
      package:
        command: (env) ->
          """
          rm -f #{dockerRoot}/deploy.tar.gz;
          tar c  . --exclude deploy --exclude=node_modules --exclude=.git --exclude=private --exclude=build --exclude=test > #{dockerRoot}/deploy.tar &&
          (tar -vrf #{dockerRoot}/deploy.tar ./config/private/#{env}_* --xform=s/#{env}_// || true) &&
          gzip #{dockerRoot}/deploy.tar
        """
      dockerize:
        command: (env) ->
          host = if env == 'production' then 'docker-reg:5001' else 'docker-reg-test:9998'
          "docker build -t #{host}/<%= pkg.name%> #{dockerRoot}"
      backup:
        command: (env) ->
          host = if env == 'production' then 'docker-reg:5001' else 'docker-reg-test:9998'
          "docker tag -f #{host}/<%= pkg.name%>:latest #{host}/<%= pkg.name%>:backup"
      revert:
        command: (env) ->
          host = if env == 'production' then 'docker-reg:5001' else 'docker-reg-test:9998'
          "docker tag -f #{host}/<%= pkg.name%>:backup #{host}/<%= pkg.name%>:latest"
      push:
        command: (env) ->
          host = if env == 'production' then 'docker-reg:5001' else 'docker-reg-test:9998'
          "docker push #{host}/<%= pkg.name%>"
      push_beta:
        command: (env) ->
          host = if env == 'production' then 'docker-reg:5001' else 'docker-reg-test:9998'
          "docker tag #{host}/<%= pkg.name%> #{host}/<%= pkg.name%>-beta && docker push #{host}/<%= pkg.name%>-beta"
      push_image:
        command: (image) ->
          "docker push #{image}"
      merge:
        command: (module, branch) ->
          "git subtree pull --prefix=local_modules/#{module} #{module} #{branch} --squash"
      push_module:
        command: (module, branch) ->
          "git push #{module} :#{branch}; git subtree push --prefix=local_modules/#{module} #{module} #{branch}"

  process.env.AWS_DEFAULT_PROFILE=grunt.config.data.pkg.awsProfile if grunt.config.data.pkg.awsProfile?

  grunt.loadNpmTasks('grunt-shell');

  grunt.registerTask 'merge', (module, branch) ->
    branch?="master"
    grunt.task.run "shell:merge:#{module}:#{branch}"

  grunt.registerTask 'push_module', (module, branch) ->
    branch?="inbound"
    grunt.task.run "shell:push_module:#{module}:#{branch}"

  grunt.registerTask 'build', (env) ->
    env?="production"
    return grunt.log.error('Environment is required') unless env?
    grunt.task.run ["shell:package:#{env}", "shell:dockerize:#{env}"]

  grunt.registerTask 'deploy', (env) ->
    env?="production"
    grunt.task.run ["shell:backup:#{env}", "build:#{env}", "shell:push:#{env}"]

  grunt.registerTask 'deploy-beta', (env) ->
    env?="production"
    grunt.task.run ["build:#{env}", "shell:push_beta:#{env}"]

  grunt.registerTask 'live', ->
    if grunt.config.data.pkg.cluster?
      grunt.task.run ['live-ecs']
    else
      grunt.task.run ['deploy', 'restart']

  grunt.registerTask 'beta', ['deploy-beta', 'restart-beta']
  grunt.registerTask 'restart', ["restart-as-group:#{grunt.config.data.pkg.autoScalingGroupName}"]
  grunt.registerTask 'emergency', ['deploy', "restart-as-group:#{grunt.config.data.pkg.autoScalingGroupName}::1"]
  grunt.registerTask 'revert', (env) ->
    env?="production"
    grunt.task.run ["shell:revert:#{env}", "shell:push:#{env}", "restart"]

  errHandler = (err, code, done) ->
    if err?
      grunt.log.writeln err
      done(false)
      return process.exit(code)

  grunt.util.spawnAndBuffer = (done, opts, cb) ->
    events = new EventEmitter()
    proc = spawn opts.cmd, opts.args
    error = []
    output = []
    all = []
    exited = false
    closed = false
    exitCode = null
    caughtError = null
    finish = ->
      if exited and closed
        cbArgs = parseArguments(cb) if cb?
        result = {stderr: Buffer.concat(error).toString(), stdout: Buffer.concat(output).toString(), code: exitCode, toString: ->Buffers.concat(all).toString()}
        errorMessage = Buffer.concat(error) if error.length > 0
        err = caughtError || if exitCode!= 0 then new Error(errorMessage || "Process exited with #{exitCode}, stderr not captured")
        return cb(err,result, exitCode) if cbArgs?.length > 2
        return errHandler(err, exitCode, done) if err?
        return cb(null, result, exitCode) if cb?
        done(exitCode==0)
    proc.stderr.on 'data', (data) ->
      if opts.captureOutput
        error.push(data)
        all.push(data)
      grunt.log.error(data) if opts.forwardOutput
    proc.stdout.on 'data', (data) ->
      if opts.captureOutput
        output.push(data)
        all.push(data)
      if opts.forwardOutput
        grunt.log.write(data)
    proc.on 'error', (err) ->
      caughtError = err
      exited = true
      exitCode = -1
    proc.on 'close', ->
      closed = true
      finish()
    proc.on 'exit', (code, signal) ->
      exited = true
      exitCode = code
      finish()
    proc

  grunt.util.bash = (done, script, cb) ->
    grunt.util.spawnAndBuffer done, {forwardOutput: true, captureOutput: false, cmd: 'bash', args: ["-c", script]}, cb

  grunt.registerTask 'dev:build', ->
    grunt.util.bash @async(), "docker build -t local/dev/#{grunt.config.data.pkg.name} ."

  grunt.registerTask 'dev', ->
    _ = require('lodash')
    grunt.util.bash @async(), """
      aws sts get-session-token > ./config/private/aws.json
    """, (err, result, code) =>
      sourceFolders = _.map grunt.config.data.pkg.additionalDevFolders || [], (f) ->
        "-v $(realpath .)/#{f}:/app/#{f}:Z"
      grunt.util.bash @async(), """
        docker run -i \\
          --net=host \\
          -v $(realpath .)/config:/app/config:Z \\
          -v $(realpath .)/src:/app/src:Z \\
          #{sourceFolders.join(' \\\n')} \\
          -e NODE_ENV=development \\
          local/dev/#{grunt.config.data.pkg.name} \\
          npm run dev
      """

  grunt.registerTask 'restart-images', (ip, key) ->
    done = @async()
    args = _.filter _.flatten([
      "-tt"
      ["-i",key] if key? and key!=""
      "ec2-user@#{ip}"
      "sudo /start-all-images.sh"
    ]), (a) -> a?
    grunt.util.spawn {cmd: "ssh", args: args}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      grunt.log.write result
      done()

  grunt.registerTask 'restart-images-by-role', (role, key) ->
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["ec2", "describe-instances"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      tasks = _(JSON.parse(result).Reservations)
        .map((r) -> r.Instances)
        .flatten()
        .filter((i) ->
          (i.IamInstanceProfile?.Arn || "").toUpperCase().match("#{role.toUpperCase()}$")?
        )
        .map((i) -> "restart-images:#{i.PrivateIpAddress}:#{key}")
        .valueOf()
      grunt.task.run tasks
      done()

  grunt.registerTask 'suspend-as-group', (asGroupName) ->
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["autoscaling", "suspend-processes", "--auto-scaling-group-name=#{asGroupName}"]}, (err, result, code) ->
      errHandler(err, code, done) if err?
      done()

  grunt.registerTask 'resume-as-group', (asGroupName) ->
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["autoscaling", "resume-processes", "--auto-scaling-group-name=#{asGroupName}"]}, (err, result, code) ->
      errHandler(err, code, done) if err?
      done()

  grunt.registerTask 'restart-as-group', (asGroupName, key, groups) ->
    groups = parseInt(groups) if groups?
    groups?=2
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["autoscaling", "describe-auto-scaling-groups", "--auto-scaling-group-names=#{asGroupName}"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      result = JSON.parse(result).AutoScalingGroups
      loadBalancers = result[0].LoadBalancerNames
      instances = _(result)
        .map((r) -> r.Instances)
        .flatten()
        .map((i) -> i.InstanceId)
        .valueOf()
      loadBalancers = "" if (groups == 1 or instances.length < 2)  #no need to remove anything from lb if we there is only one group
      grunt.util.spawn {cmd: "aws", args: ["ec2", "describe-instances", "--instance-ids", instances...]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        tasks = _(JSON.parse(result).Reservations)
          .map((r) -> r.Instances)
          .flatten()
          .groupBy((r, i) -> i%groups)
          .map((instances, set) ->
            ids = _.map instances, (i) -> i.InstanceId
            ips = _.map instances, (i) -> i.PrivateIpAddress
            "restart-as-images:#{loadBalancers}:#{ids}:#{ips}:#{key}"
          )
          .valueOf()
        if tasks.length > 0
          tasks = ["suspend-as-group:#{asGroupName}", tasks..., "resume-as-group:#{asGroupName}"]
          grunt.task.run tasks
        done()

  grunt.registerTask 'deregister-lb-instance', (lbName, instanceIds) ->
    return unless lbName.length > 0 and instanceIds.length > 0
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["elb", "deregister-instances-from-load-balancer", "--load-balancer-name", lbName, "--instances", instanceIds.split(',')...]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      done()

  grunt.registerTask 'register-lb-instance', (lbName, instanceIds) ->
    return unless lbName.length > 0 and instanceIds.length > 0
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ["elb", "register-instances-with-load-balancer", "--load-balancer-name", lbName, "--instances", instanceIds.split(',')...]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      done()

  grunt.registerTask 'wait-for-lb-instance-state', (lbName, state, instanceIds) ->
    return unless lbName.length > 0 and instanceIds.length > 0
    done = @async()
    timeout = 2 * 1000
    maxCount = 240
    grunt.log.write "Checking [#{instanceIds}] in [#{lbName}]"
    checkInstancesInService = (count, cb) ->
      grunt.log.write "."
      grunt.util.spawn {cmd: "aws", args: ["elb", "describe-instance-health", "--load-balancer-name", lbName, "--instances", instanceIds.split(',')...]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        notInState = _.reject JSON.parse(result).InstanceStates, (instanceState) -> instanceState.State == state
        return cb(true) if notInState.length == 0
        return cb(false) if count>=maxCount
        setTimeout (-> checkInstancesInService(count+1, cb)), timeout
    checkInstancesInService 0, (inService) ->
      return done() if inService
      grunt.log.write "Instances [#{instanceIds}] in [#{lbName}] did not achieve [#{state}] after #{timeout*maxCount/1000} seconds"
      done()
      return process.exit(-1)

  parallelTasks = {}
  grunt.registerTask 'parallel', (args...) ->
    task = args.join(':')
    done = ->
      parallelTasks[task]=true
    parallelTasks[task]=false

    grunt.util.spawn {grunt: true, args: task, opts: {stdio: 'inherit'}}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      done()

  grunt.registerTask 'parallel-barrier', ->
    done = @async()
    isDone = ->
      for own k,v of parallelTasks
        if v != true
          return setTimeout isDone, 1000
      done()
    isDone()

  grunt.registerTask 'restart-as-images', (lbNames, instanceIds, ipAddresses, key) ->
    tasks = []
    _.each lbNames.split(','), (lb) ->
      tasks.push "parallel:deregister-lb-instance:#{lb}:#{instanceIds}"
    tasks.push "parallel-barrier"
    _.each lbNames.split(','), (lb) ->
      tasks.push "parallel:wait-for-lb-instance-state:#{lb}:OutOfService:#{instanceIds}"
    tasks.push "parallel-barrier"
    _.each ipAddresses.split(","), (ipAddress) -> tasks.push "parallel:restart-images:#{ipAddress}:#{key}"
    tasks.push "parallel-barrier"
    _.each lbNames.split(','), (lb) ->
      tasks.push "parallel:register-lb-instance:#{lb}:#{instanceIds}"
    tasks.push "parallel-barrier"
    _.each lbNames.split(','), (lb) ->
      tasks.push "parallel:wait-for-lb-instance-state:#{lb}:InService:#{instanceIds}"
    tasks.push "parallel-barrier"
    grunt.task.run tasks

  grunt.registerTask 'remove-instances-from-parent-as', (ips, doNotTerminate) ->
    done = @async()
    grunt.util.spawn {cmd:"aws", args: ["ec2","describe-instances" ,"--filters","Name=private-ip-address,Values=#{ips}"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      instances = _(JSON.parse(result).Reservations)
        .map((r) -> r.Instances)
        .flatten()
        .map((i) -> {instanceId: i.InstanceId, ip: i.PrivateIpAddress})
        .value()
      instanceIds = _.map instances, (i) -> i.instanceId
      instances = _.groupBy instances, 'instanceId'
      instances[k]=v[0] for k,v of instances
      grunt.util.spawn {cmd:"aws", args: ["autoscaling", "describe-auto-scaling-instances","--instance-ids", instanceIds...]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        _.each JSON.parse(result).AutoScalingInstances, (i) ->
          instances[i.InstanceId].asGroupName = i.AutoScalingGroupName
        instancesByGroup = _.groupBy instances, 'asGroupName'
        tasks = _.map instancesByGroup, (instances, group) ->
          "remove-instances-from-as:#{group}:#{_.map(instances, (i) -> i.ip)}:#{doNotTerminate}"
        grunt.task.run tasks
        done()

  grunt.registerTask 'remove-instances-from-as', (asGroup, ips, doNotTerminate) ->
    done = @async()
    grunt.util.spawn {cmd:"aws", args: ["ec2","describe-instances" ,"--filters","Name=private-ip-address,Values=#{ips}"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      instanceIds = _(JSON.parse(result).Reservations)
        .map((r) -> r.Instances)
        .flatten()
        .map((i) -> i.InstanceId)
        .value()
      grunt.util.spawn {cmd: "aws", args: ["autoscaling", "describe-auto-scaling-groups", "--auto-scaling-group-names=#{asGroup}"]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        result = JSON.parse(result).AutoScalingGroups
        lbNames = result[0].LoadBalancerNames
        tasks = []
        _.each lbNames, (lb) ->
          tasks.push "deregister-lb-instance:#{lb}:#{instanceIds.join(',')}"
          tasks.push "wait-for-lb-instance-state:#{lb}:OutOfService:#{instanceIds.join(',')}"
        tasks.push "detach-and-terminate-instances:#{asGroup}:#{instanceIds.join(',')}" unless doNotTerminate == 'true'
        grunt.task.run tasks
        done()

  grunt.registerTask 'detach-and-terminate-instances', (asGroup, instanceIds) ->
    done = @async()
    instances = instanceIds.split(',')
    grunt.util.spawn {cmd:"aws", args:["autoscaling", "detach-instances", "--auto-scaling-group-name", asGroup, "--should-decrement-desired-capacity", "--instance-ids", instances...]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      grunt.util.spawn {cmd:"aws", args:["ec2", "terminate-instances", "--instance-ids", instances...]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        console.log "SHUTTING DOWN :", instances
        done()

  grunt.registerTask 'push-config', (env) ->
    keyId = grunt.config.data.pkg.name
    bucket = grunt.config.data.pkg.configBucket
    throw new Error("Bucket is required") unless bucket?
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ['kms', "encrypt", "--key-id", "alias/config/#{keyId}", "--plaintext", "fileb://config/private/#{env}.json", "--output", "text", "--query", "CiphertextBlob"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      fs = require('fs')
      fs.writeFileSync("config/private/#{env}.json.enc", result.stdout)
      path = "s3://#{bucket}/#{keyId}/#{env}.json"
      grunt.util.spawn {cmd: "aws", args: ['s3', "cp", "config/private/#{env}.json.enc", path]}, (err, result, code) ->
        fs.unlinkSync("config/private/#{env}.json.enc")
        return errHandler(err, code, done) if err?


  ### ECS TASKS ###
  grunt.registerTask 'push-ecr', () ->
    repoName = grunt.config.data.pkg.name
    throw new Error("Bucket is required") unless repoName?
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ['ecr', "describe-repositories", "--repository-name=#{repoName}", "--query=repositories[0].repositoryUri"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      repoUrl = JSON.parse(result.stdout)
      grunt.util.spawn {cmd: "docker", args: "tag -f docker-reg:5001/#{repoName} #{repoUrl}".split(' ')}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        grunt.util.spawn {cmd: "docker", args: ['push', repoUrl]}, (err, result, code) ->
          return errHandler(err, code, done) if err?
          grunt.log.write result.stdout
          done()

  grunt.registerTask 'new-ecs-revision', ->
    name = grunt.config.data.pkg.name
    throw new Error("Bucket is required") unless name?
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ['ecs', "describe-task-definition", "--task-definition=#{name}"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      taskDef = JSON.parse(result.stdout).taskDefinition
      delete taskDef.status
      delete taskDef.taskDefinitionArn
      delete taskDef.revision
      delete taskDef.requiresAttributes
      grunt.util.spawn {cmd: "aws", args: ['ecs', "register-task-definition", "--cli-input-json", JSON.stringify(taskDef)]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        grunt.log.write result.stdout
        done()

  grunt.registerTask 'update-ecs-service', ->
    name = grunt.config.data.pkg.name
    cluster = grunt.config.data.pkg.cluster
    throw new Error("Bucket is required") unless name?
    done = @async()
    grunt.util.spawn {cmd: "aws", args: ['ecs', "describe-task-definition", "--task-definition=#{name}"]}, (err, result, code) ->
      return errHandler(err, code, done) if err?
      taskDef = JSON.parse(result.stdout).taskDefinition
      throw new Error("No task definition found") unless taskDef?.revision?
      grunt.util.spawn {cmd: "aws", args: ['ecs', "update-service", "--task-definition=#{name}:#{taskDef.revision}", "--service=#{name}", "--cluster=#{cluster}"]}, (err, result, code) ->
        return errHandler(err, code, done) if err?
        grunt.log.write result.stdout
        done()

  grunt.registerTask 'restart-ecs', ['new-ecs-revision', 'update-ecs-service']
  grunt.registerTask 'deploy-ecs', ['build', 'push-ecr']
  grunt.registerTask 'live-ecs', ['deploy-ecs', 'restart-ecs']
