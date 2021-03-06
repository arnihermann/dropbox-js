buildClientTests = (clientKeys) ->
  # Creates the global client.
  setupClient = (test, done) ->
    # Should only be used for fixture teardown.
    test.__client = new Dropbox.Client clientKeys
    done()

  # Creates the test directory.
  setupDirectory = (test, done) ->
    # True if running on node.js
    test.node_js = module? and module?.exports? and require?

    # All test data should go here.
    test.testFolder = '/js tests.' + Math.random().toString(36)
    test.__client.mkdir test.testFolder, (error, stat) ->
      expect(error).to.equal null
      done()

  # Creates the binary image file in the test directory.
  setupImageFile = (test, done) ->
    test.imageFile = "#{test.testFolder}/test-binary-image.png"
    test.imageFileData = testImageBytes

    # Firefox has a bug that makes writing binary files fail.
    # https://bugzilla.mozilla.org/show_bug.cgi?id=649150
    if Blob? and (test.node_js or
                  window.navigator.userAgent.indexOf('Gecko') isnt -1)
      testImageServerOn()
      Dropbox.Xhr.request2('GET', testImageUrl, {}, null, null, 'blob',
          (error, blob) =>
            testImageServerOff()
            expect(error).to.equal null
            test.__client.writeFile test.imageFile, blob, (error, stat) ->
              expect(error).to.equal null
              test.imageFileTag = stat.versionTag
              done()
          )
    else
      test.__client.writeFile(test.imageFile, test.imageFileData,
          { binary: true },
          (error, stat) ->
            expect(error).to.equal null
            test.imageFileTag = stat.versionTag
            done()
          )

  # Creates the plaintext file in the test directory.
  setupTextFile = (test, done) ->
    test.textFile = "#{test.testFolder}/test-file.txt"
    test.textFileData = "Plaintext test file #{Math.random().toString(36)}.\n"
    test.__client.writeFile(test.textFile, test.textFileData,
        (error, stat) ->
          expect(error).to.equal null
          test.textFileTag = stat.versionTag
          done()
        )

  # Global (expensive) fixtures.
  before (done) ->
    @timeout 10 * 1000
    setupClient this, =>
      setupDirectory this, =>
        setupImageFile this, =>
          setupTextFile this, ->
            done()

  # Teardown for global fixtures.
  after (done) ->
    @__client.remove @testFolder, (error, stat) ->
      expect(error).to.equal null
      done()

  # Per-test (cheap) fixtures.
  beforeEach ->
    @timeout 8 * 1000
    @client = new Dropbox.Client clientKeys

  describe 'URLs for custom API server', ->
    it 'computes the other URLs correctly', ->
      client = new Dropbox.Client
        key: clientKeys.key,
        secret: clientKeys.secret,
        server: 'https://api.sandbox.dropbox-proxy.com'

      expect(client.apiServer).to.equal(
        'https://api.sandbox.dropbox-proxy.com')
      expect(client.authServer).to.equal(
        'https://www.sandbox.dropbox-proxy.com')
      expect(client.fileServer).to.equal(
        'https://api-content.sandbox.dropbox-proxy.com')

  describe 'normalizePath', ->
    it "doesn't touch relative paths", ->
      expect(@client.normalizePath('aa/b/cc/dd')).to.equal 'aa/b/cc/dd'

    it 'removes the leading / from absolute paths', ->
      expect(@client.normalizePath('/aaa/b/cc/dd')).to.equal 'aaa/b/cc/dd'

    it 'removes multiple leading /s from absolute paths', ->
      expect(@client.normalizePath('///aa/b/ccc/dd')).to.equal 'aa/b/ccc/dd'

  describe 'urlEncodePath', ->
    it 'encodes each segment separately', ->
      expect(@client.urlEncodePath('a b+c/d?e"f/g&h')).to.
          equal "a%20b%2Bc/d%3Fe%22f/g%26h"
    it 'normalizes paths', ->
      expect(@client.urlEncodePath('///a b+c/g&h')).to.
          equal "a%20b%2Bc/g%26h"

  describe 'dropboxUid', ->
    it 'matches the uid in the credentials', ->
      expect(@client.dropboxUid()).to.equal clientKeys.uid

  describe 'getUserInfo', ->
    it 'returns reasonable information', (done) ->
      @client.getUserInfo (error, userInfo, rawUserInfo) ->
        expect(error).to.equal null
        expect(userInfo).to.be.instanceOf Dropbox.UserInfo
        expect(userInfo.uid).to.equal clientKeys.uid
        expect(rawUserInfo).not.to.be.instanceOf Dropbox.UserInfo
        expect(rawUserInfo).to.have.property 'uid'
        done()

  describe 'mkdir', ->
    afterEach (done) ->
      return done() unless @newFolder
      @client.remove @newFolder, (error, stat) -> done()

    it 'creates a folder in the test folder', (done) ->
      @newFolder = "#{@testFolder}/test'folder"
      @client.mkdir @newFolder, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFolder
        expect(stat.isFolder).to.equal true
        @client.stat @newFolder, (error, stat) =>
          expect(error).to.equal null
          expect(stat.isFolder).to.equal true
          done()

  describe 'readFile', ->
    it 'reads a text file', (done) ->
      @client.readFile @textFile, (error, data, stat) =>
        expect(error).to.equal null
        expect(data).to.equal @textFileData
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @textFile
          expect(stat.isFile).to.equal true
        done()

    it 'reads a binary file into a string', (done) ->
      @client.readFile @imageFile, { binary: true }, (error, data, stat) =>
        expect(error).to.equal null
        expect(data).to.equal @imageFileData
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @imageFile
          expect(stat.isFile).to.equal true
        done()

    it 'reads a binary file into a Blob', (done) ->
      return done() unless Blob?
      @client.readFile @imageFile, { blob: true }, (error, blob, stat) =>
        expect(error).to.equal null
        expect(blob).to.be.instanceOf Blob
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @imageFile
          expect(stat.isFile).to.equal true
        reader = new FileReader
        reader.onloadend = =>
          return unless reader.readyState == FileReader.DONE
          expect(reader.result).to.equal @imageFileData
          done()
        reader.readAsBinaryString blob

  describe 'writeFile', ->
    afterEach (done) ->
      @timeout 5 * 1000  # The current API server is slow on this sometimes.
      return done() unless @newFile
      @client.remove @newFile, (error, stat) -> done()

    it 'writes a new text file', (done) ->
      @timeout 5 * 1000  # The current API server is slow on this sometimes.
      @newFile = "#{@testFolder}/another text file.txt"
      @newFileData = "Another plaintext file #{Math.random().toString(36)}."
      @client.writeFile @newFile, @newFileData, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFile
        expect(stat.isFile).to.equal true
        @client.readFile @newFile, (error, data, stat) =>
          expect(error).to.equal null
          expect(data).to.equal @newFileData
          unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
            expect(stat).to.be.instanceOf Dropbox.Stat
            expect(stat.path).to.equal @newFile
            expect(stat.isFile).to.equal true
          done()

    it 'writes a new empty file', (done) ->
      @timeout 5 * 1000  # The current API server is slow on this sometimes.
      @newFile = "#{@testFolder}/another text file.txt"
      @newFileData = ''
      @client.writeFile @newFile, @newFileData, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFile
        expect(stat.isFile).to.equal true
        @client.readFile @newFile, (error, data, stat) =>
          expect(error).to.equal null
          expect(data).to.equal @newFileData
          unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
            expect(stat).to.be.instanceOf Dropbox.Stat
            expect(stat.path).to.equal @newFile
            expect(stat.isFile).to.equal true
          done()

    # TODO(pwnall): tests for writing binary files


  describe 'stat', ->
    it 'retrieves a Stat for a file', (done) ->
      @timeout 5 * 1000  # The current API server is slow on this sometimes.
      @client.stat @textFile, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @textFile
        expect(stat.isFile).to.equal true
        expect(stat.versionTag).to.equal @textFileTag
        expect(stat.size).to.equal @textFileData.length
        if clientKeys.sandbox
          expect(stat.inAppFolder).to.equal true
        else
          expect(stat.inAppFolder).to.equal false
        done()

    it 'retrieves a Stat for a folder', (done) ->
      @client.stat @testFolder, (error, stat, entries) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @testFolder
        expect(stat.isFolder).to.equal true
        expect(stat.size).to.equal 0
        if clientKeys.sandbox
          expect(stat.inAppFolder).to.equal true
        else
          expect(stat.inAppFolder).to.equal false
        expect(entries).to.equal undefined
        done()

    it 'retrieves a Stat and entries for a folder', (done) ->
      @client.stat @testFolder, { readDir: true }, (error, stat, entries) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @testFolder
        expect(stat.isFolder).to.equal true
        expect(entries).to.be.ok
        expect(entries).to.have.length 2
        expect(entries[0]).to.be.instanceOf Dropbox.Stat
        expect(entries[0].path).not.to.equal @testFolder
        expect(entries[0].path).to.have.string @testFolder
        done()

    it 'fails cleanly for a non-existing path', (done) ->
      @client.stat @testFolder + '/should_404.txt', (error, stat, entries) =>
        expect(stat).to.equal undefined
        expect(entries).to.equal.null
        expect(error).to.be.instanceOf Dropbox.ApiError
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do status codes.
          expect(error).to.have.property 'status'
          expect(error.status).to.equal 404
        done()

  describe 'readdir', ->
    it 'retrieves a Stat and entries for a folder', (done) ->
      @client.readdir @testFolder, (error, entries, dir_stat, entry_stats) =>
        expect(error).to.equal null
        expect(entries).to.be.ok
        expect(entries).to.have.length 2
        expect(entries[0]).to.be.a 'string'
        expect(entries[0]).not.to.have.string '/'
        expect(entries[0]).to.match /^(test-binary-image.png)|(test-file.txt)$/
        expect(dir_stat).to.be.instanceOf Dropbox.Stat
        expect(dir_stat.path).to.equal @testFolder
        expect(dir_stat.isFolder).to.equal true
        expect(entry_stats).to.be.ok
        expect(entry_stats).to.have.length 2
        expect(entry_stats[0]).to.be.instanceOf Dropbox.Stat
        expect(entry_stats[0].path).not.to.equal @testFolder
        expect(entry_stats[0].path).to.have.string @testFolder
        done()

  describe 'history', ->
    it 'gets a list of revisions', (done) ->
      @client.history @textFile, (error, versions) =>
        expect(error).to.equal null
        expect(versions).to.have.length 1
        expect(versions[0]).to.be.instanceOf Dropbox.Stat
        expect(versions[0].path).to.equal @textFile
        expect(versions[0].size).to.equal @textFileData.length
        expect(versions[0].versionTag).to.equal @textFileTag
        done()

  describe 'copy', ->
    afterEach (done) ->
      return done() unless @newFile
      @client.remove @newFile, (error, stat) -> done()

    it 'copies a file given by path', (done) ->
      @timeout 12 * 1000  # This sequence is slow on the current API server.

      @newFile = "#{@testFolder}/copy of test-file.txt"
      @client.copy @textFile, @newFile, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFile
        @client.readFile @newFile, (error, data, stat) =>
          expect(error).to.equal null
          expect(data).to.equal @textFileData
          unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
            expect(stat).to.be.instanceOf Dropbox.Stat
            expect(stat.path).to.equal @newFile
          @client.readFile @textFile, (error, data, stat) =>
            expect(error).to.equal null
            expect(data).to.equal @textFileData
            unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
              expect(stat).to.be.instanceOf Dropbox.Stat
              expect(stat.path).to.equal @textFile
              expect(stat.versionTag).to.equal @textFileTag
            done()

  describe 'makeCopyReference', ->
    afterEach (done) ->
      return done() unless @newFile
      @client.remove @newFile, (error, stat) -> done()

    it 'creates a Dropbox.CopyReference that copies the file', (done) ->
      @timeout 12 * 1000  # This sequence is slow on the current API server.
      @newFile = "#{@testFolder}/ref copy of test-file.txt"

      @client.makeCopyReference @textFile, (error, copyRef) =>
        expect(error).to.equal null
        expect(copyRef).to.be.instanceOf Dropbox.CopyReference
        @client.copy copyRef, @newFile, (error, stat) =>
          expect(error).to.equal null
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @newFile
          expect(stat.isFile).to.equal true
          @client.readFile @newFile, (error, data, stat) =>
            expect(error).to.equal null
            expect(data).to.equal @textFileData
            unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
              expect(stat).to.be.instanceOf Dropbox.Stat
              expect(stat.path).to.equal @newFile
            done()

  describe 'move', ->
    beforeEach (done) ->
      @timeout 10 * 1000  # This sequence is slow on the current API server.
      @moveFrom = "#{@testFolder}/move source of test-file.txt"
      @client.copy @textFile, @moveFrom, (error, stat) ->
        expect(error).to.equal null
        done()

    afterEach (done) ->
      @timeout 5 * 1000  # This sequence is slow on the current API server.
      @client.remove @moveFrom, (error, stat) =>
        return done() unless @moveTo
        @client.remove @moveTo, (error, stat) -> done()

    it 'moves a file', (done) ->
      @timeout 15 * 1000  # This sequence is slow on the current API server.
      @moveTo = "#{@testFolder}/moved test-file.txt"
      @client.move @moveFrom, @moveTo, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @moveTo
        expect(stat.isFile).to.equal true
        @client.readFile @moveTo, (error, data, stat) =>
          expect(error).to.equal null
          expect(data).to.equal @textFileData
          unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
            expect(stat).to.be.instanceOf Dropbox.Stat
            expect(stat.path).to.equal @moveTo
          @client.readFile @moveFrom, (error, data, stat) ->
            expect(error).to.be.ok
            unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do status codes.
              expect(error).to.have.property 'status'
              expect(error.status).to.equal 404
            expect(data).to.equal undefined
            unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
              expect(stat).to.equal undefined
            done()

  describe 'remove', ->
    beforeEach (done) ->
      @timeout 5 * 1000  # This sequence is slow on the current API server.
      @newFolder = "#{@testFolder}/folder delete test"
      @client.mkdir @newFolder, (error, stat) =>
        expect(error).to.equal null
        done()

    afterEach (done) ->
      return done() unless @newFolder
      @client.remove @newFolder, (error, stat) -> done()

    it 'deletes a folder', (done) ->
      @client.remove @newFolder, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFolder
        @client.stat @newFolder, { removed: true }, (error, stat) =>
          expect(error).to.equal null
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.isRemoved).to.equal true
          done()

    it 'deletes a folder when called as unlink', (done) ->
      @client.unlink @newFolder, (error, stat) =>
        expect(error).to.equal null
        expect(stat).to.be.instanceOf Dropbox.Stat
        expect(stat.path).to.equal @newFolder
        @client.stat @newFolder, { removed: true }, (error, stat) =>
          expect(error).to.equal null
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.isRemoved).to.equal true
          done()

  describe 'revertFile', ->
    describe 'on a removed file', ->
      beforeEach (done) ->
        @timeout 12 * 1000  # This sequence seems to be quite slow.

        @newFile = "#{@testFolder}/file revert test.txt"
        @client.copy @textFile, @newFile, (error, stat) =>
          expect(error).to.equal null
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @newFile
          @versionTag = stat.versionTag
          @client.remove @newFile, (error, stat) =>
            expect(error).to.equal null
            expect(stat).to.be.instanceOf Dropbox.Stat
            expect(stat.path).to.equal @newFile
            done()

      afterEach (done) ->
        return done() unless @newFile
        @client.remove @newFile, (error, stat) -> done()

      it 'reverts the file to a previous version', (done) ->
        @timeout 12 * 1000  # This sequence seems to be quite slow.

        @client.revertFile @newFile, @versionTag, (error, stat) =>
          expect(error).to.equal null
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @newFile
          expect(stat.isRemoved).to.equal false
          @client.readFile @newFile, (error, data, stat) =>
            expect(error).to.equal null
            expect(data).to.equal @textFileData
            unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
              expect(stat).to.be.instanceOf Dropbox.Stat
              expect(stat.path).to.equal @newFile
              expect(stat.isRemoved).to.equal false
            done()

  describe 'findByName', ->
    it 'locates the test folder given a partial name', (done) ->
      namePattern = @testFolder.substring 5
      @client.search '/', namePattern, (error, matches) =>
        expect(error).to.equal null
        expect(matches).to.have.length 1
        expect(matches[0]).to.be.instanceOf Dropbox.Stat
        expect(matches[0].path).to.equal @testFolder
        expect(matches[0].isFolder).to.equal true
        done()

  describe 'makeUrl for a short Web URL', ->
    it 'returns a shortened Dropbox URL', (done) ->
      @client.makeUrl @textFile, (error, publicUrl) ->
        expect(error).to.equal null
        expect(publicUrl).to.be.instanceOf Dropbox.PublicUrl
        expect(publicUrl.isDirect).to.equal false
        expect(publicUrl.url).to.contain '//db.tt/'
        done()

  describe 'makeUrl for a Web URL', ->
    it 'returns an URL to a preview page', (done) ->
      @client.makeUrl @textFile, { long: true }, (error, publicUrl) =>
        expect(error).to.equal null
        expect(publicUrl).to.be.instanceOf Dropbox.PublicUrl
        expect(publicUrl.isDirect).to.equal false
        expect(publicUrl.url).not.to.contain '//db.tt/'

        # The contents server does not return CORS headers.
        return done() unless @nodejs
        Dropbox.Xhr.request 'GET', publicUrl.url, {}, null, (error, data) ->
          expect(error).to.equal null
          expect(data).to.contain '<!DOCTYPE html>'
          done()

  describe 'makeUrl for a direct download URL', ->
    it 'gets a direct download URL', (done) ->
      @client.makeUrl @textFile, { download: true }, (error, publicUrl) =>
        expect(error).to.equal null
        expect(publicUrl).to.be.instanceOf Dropbox.PublicUrl
        expect(publicUrl.isDirect).to.equal true
        expect(publicUrl.url).not.to.contain '//db.tt/'

        # The contents server does not return CORS headers.
        return done() unless @nodejs
        Dropbox.Xhr.request 'GET', publicUrl.url, {}, null, (error, data) =>
          expect(error).to.equal null
          expect(data).to.equal @textFileData
          done()

  describe 'pullChanges', ->
    afterEach (done) ->
      @timeout 5 * 1000  # The current API server is slow on this sometimes.
      return done() unless @newFile
      @client.remove @newFile, (error, stat) -> done()

    it 'gets a cursor, then it gets relevant changes', (done) ->
      # Pulling an entire Dropbox can take a lot of time, so we need fancy
      # logic here.
      @timeoutValue = 10 * 1000
      @timeout @timeoutValue

      @client.pullChanges (error, changes) =>
        expect(error).to.equal null
        expect(changes).to.be.instanceOf Dropbox.PulledChanges
        expect(changes.blankSlate).to.equal true

        # Calls pullChanges until it's done listing the user's Dropbox.
        drainEntries = (client, callback) =>
          return callback() unless changes.shouldPullAgain
          @timeoutValue += 2 * 1000  # 2 extra seconds per call
          @timeout @timeoutValue
          client.pullChanges changes, (error, _changes) ->
            expect(error).to.equal null
            changes = _changes
            drainEntries client, callback
        drainEntries @client, =>

          @newFile = "#{@testFolder}/delta-test.txt"
          newFileData = "This file is used to test the pullChanges method.\n"
          @client.writeFile @newFile, newFileData, (error, stat) =>
            expect(error).to.equal null
            expect(stat).to.have.property 'path'
            expect(stat.path).to.equal @newFile

            @client.pullChanges changes, (error, changes) =>
              expect(error).to.equal null
              expect(changes).to.be.instanceof Dropbox.PulledChanges
              expect(changes.blankSlate).to.equal false
              expect(changes.changes).to.have.length.greaterThan 0
              change = changes.changes[changes.changes.length - 1]
              expect(change).to.be.instanceOf Dropbox.PullChange
              expect(change.path).to.equal @newFile
              expect(change.wasRemoved).to.equal false
              expect(change.stat.path).to.equal @newFile
              done()

  describe 'thumbnailUrl', ->
    it 'produces an URL that contains the file name', ->
      url = @client.thumbnailUrl @imageFile, { png: true, size: 'medium' }
      expect(url).to.contain 'tests'  # Fragment of the file name.
      expect(url).to.contain 'png'
      expect(url).to.contain 'medium'

  describe 'readThumbnail', ->
    it 'reads the image into a string', (done) ->
      @timeout 12 * 1000  # Thumbnail generation is slow.
      @client.readThumbnail @imageFile, { png: true }, (error, data, stat) =>
        expect(error).to.equal null
        expect(data).to.be.a 'string'
        expect(data).to.contain 'PNG'
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @imageFile
          expect(stat.isFile).to.equal true
        done()

    it 'reads the image into a Blob', (done) ->
      return done() unless Blob?
      @timeout 12 * 1000  # Thumbnail generation is slow.
      options = { png: true, blob: true }
      @client.readThumbnail @imageFile, options, (error, blob, stat) =>
        expect(error).to.equal null
        expect(blob).to.be.instanceOf Blob
        unless Dropbox.Xhr.ieMode  # IE's XDR doesn't do headers.
          expect(stat).to.be.instanceOf Dropbox.Stat
          expect(stat.path).to.equal @imageFile
          expect(stat.isFile).to.equal true
        reader = new FileReader
        reader.onloadend = =>
          return unless reader.readyState == FileReader.DONE
          expect(reader.result).to.contain 'PNG'
          done()
        reader.readAsBinaryString blob

describe 'DropboxClient with full Dropbox access', ->
  buildClientTests testFullDropboxKeys

describe 'DropboxClient with Folder access', ->
  buildClientTests testKeys

  describe 'authenticate', ->
    # NOTE: we're not duplicating this test in the full Dropbox acess suite,
    #       because it's annoying to the tester
    it 'completes the flow', (done) ->
      @timeout 30 * 1000  # Time-consuming because the user must click.
      @client.reset()
      @client.authDriver authDriver
      @client.authenticate (error, client) =>
        expect(error).to.equal null
        expect(client).to.equal @client
        done()

