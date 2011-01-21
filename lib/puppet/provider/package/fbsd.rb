######
#
#  Freebsd package provider
#
#   Used for handling freebsd packages (ie: precompiled ports) only.
#
#

require 'puppet/provider/package'
Puppet::Type.type(:package).provide :fbsd, :parent => Puppet::Provider::Package do

  desc "Package management for Freebsd using base OS tools only.  This provider
    is designed for using precompiled packages (.tbz) files only.  Set :source to
    be the local path or URL to use to the package file. Set the resource :name
    to the full package origin (eg: ftp/wget for wget application) and set :alias
    to your own simple name. This provider does not auto-install dependencies, 
    nor error if they're not found on install."

  # Operating restrictions/Suitability requirements
  # defaultfor :operatingsystem => :freebsd   # uncomment when approved by someone important
  confine   :operatingsystem => :freebsd
  commands  :pkgadd   => "/usr/sbin/pkg_add",
            :pkginfo  => "/usr/sbin/pkg_info",
            :pkgdel   => "/usr/sbin/pkg_delete",
            :pkgver   => "/usr/sbin/pkg_version"

  ##### debug command/method
      # Wrapper method for output.

  def debugline(line)
    # Find calling method's name to log (found code on 'net)
    srcname = caller[0][/`([^']*)'/, 1]
    # Find calling method's calling method
    # srcsrcname = caller[1][/`([^']*)'/, 1]

    if @resource 
      # output = resource.method: data.
      Puppet.debug ("#{@resource}.#{srcname}: #{line}")
    else
      Puppet.debug ("[no resource].#{srcname}: #{line}")
    end 
  end
    

  ##### Instances command/method 
      # Parameters needed:
      #   -none-
      # Parameters returned
      #   :ensure       - package version
      #   :name         - package name (internal name to Freebsd ie: port origin)
      #   :description  - package shortname (what it's commonly called)

  def self.instances
    Puppet.debug "fbsd.instances called"

    # Define variables
    packages = []
    hash = Hash.new

    # Call pkginfo to get installed listing
    cmdline = ["-aoQ"]
    begin
      output = pkginfo(*cmdline)
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new(output)
      return nil
    end

    # Parse output by loop per line and regex values
    # output line format: "app-1.2.3:util/app" ie: "shortname-version:origin"
    # Note that shortname can contain dashes, so anchor on the colon.
    regex = %r{^(\S+)-([^-\s]+):(\S+)$}
    fields = [:description, :ensure, :name]
    linecount = output.split("\n").count
    output.split("\n").each { |dataline|
      hash.clear
      if match = regex.match(dataline)
        # Regex was successful - populate data
        fields.zip(match.captures) { |field, value|
          hash[field] = value
        }

        # Add to packages array
        packages << new(hash)
      else
        # Line didn't match regex - skip
        Puppet.debug "fbsd.instances - skipped dataline (#{dataline})"
      end
    } # output.split

    # Return package listing
    Puppet.debug "fbsd.instances - Packages found #{packages.count} out of #{linecount}"
    return packages

  end   # def instances



  ##### Installation Command/method
      # Parameter needed:
      #   :name     = package origin to install
      #   :ensure   = version of the package to install (if a choice), or whatever
      #   :source   = the package file/URL
      # Parameters returned:
      #   -none-

  def install
    debugline "Installing Package (#{@resource[:name]}) from (#{@resource[:source]})"

    # Force that a .tbz file is referenced, and not something else which can go weird.
    if @resource[:source] =~ /\.tbz$/

    	# Call pkginfo on the source package to verify :name = portorigin
      cmdline = ["-qo", @resource[:source] ]
      begin
        output = pkginfo(*cmdline)
      rescue Puppet::ExecutionFailure
        raise Puppet::Error.new(output)
      end

      if output =~ /^(\S+)$/
        if $1 == @resource[:name]
          # Call pkgadd to get installed listing
          cmdline = ["--verbose", "--no-deps", @resource[:source]]
          begin
            output = pkgadd(*cmdline)
          rescue Puppet::ExecutionFailure
            raise Puppet::Error.new(output)
            return nil
          end
        else
          Puppet.err "Package source portorigin (#{$1}) doesn't match :name (#{@resource[:name]}) - not installing"
          return nil
        end   # if
      end   # if
    else
      Puppet.err "Package source not a .tbz file (#{@resource[:source]})"
      return nil
    end   # if
  end   # def



  ##### Query Command/Method
      # Parameters needed:
      #   :name         = port origin
      # Fields required/used:
      #   :ensure       = port version
      #   :description  = shortname

  def query
    debugline "Query made on (#{@resource[:name]})"

    hash = Hash.new

    # Call pkginfo on the source package (maybe updated!)
    cmdline = ["-qO", @resource[:name] ]
    begin
      output = pkginfo(*cmdline)
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new(output)
      return nil
    end

    if output =~ /^(\S+)-([^-\s]+)$/
      hash.clear
      hash[:ensure]       = $2
      hash[:description]  = $1
      hash[:name]         = @resource[:name]

      return hash
    else
      # Didn't parse correctly, FIXME: Can be more than one package installed (an error)
      debugline "ERROR : output can't be parsed (#{output})"
      return nil
    end   # if
  
    # Return 'nil' since we shouldn't get here.
    return nil
  end   # def

    
  ##### uninstall command/method
      # Parameters needed:
      #   :name
      # Parameters returned:
      #   -none-

  def uninstall
    debugline "called on #{@resource[:name]}"

    # Get full package name from port origin to uninstall with
    cmdline = ["-qO", @resource[:name]]
    begin
      output = pkginfo(*cmdline)
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new(output)
    end

    # Must loop since it's possible to install multiple versions of the same
    # code from the same portorigin.  All-but-one will be broken (99% of the time)
    output.split("\n").each { |data|
      if data =~ /^(\S+)$/
        # uninstall the package
        debugline "removing #{data}"
        cmdline = [ "--verbose", $1 ]
        begin
          output = pkgdel(*cmdline)
        rescue Puppet::ExecutionFailure
          raise Puppet::Error.new(output)
          return nil
        end   # begin
      else
        debugline "invalid package, skipping : (#{$1}) extracted from (#{data})"
      end   # if
    }   # each

  end   # def


  ##### update command/method
      # Parameters needed:
      #   :name
      #   :source
      # Parameters/Values returned:
      #   -none-

  def update
    debugline "called for #{@resource[:name]}"

    # uninstall the old package

    # Get full package name from port origin to uninstall with
    cmdline = ["-qO", @resource[:name]]
    begin
      output = pkginfo(*cmdline)
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new(output)
    end

    # Must loop since it's possible to install multiple versions of the same
    # code from the same portorigin.  All-but-one will be broken (99% of the time)

    # Weirdly, we must now "force" the deletion due to possible dependencies 
    # (and hope it'll be replaced correctly)
    output.split("\n").each { |data|
      if data =~ /^(\S+)$/
        # uninstall the package
        debugline "removing #{data}"
        cmdline = [ "--verbose", "--force", $1 ]
        begin
          output = pkgdel(*cmdline)
        rescue Puppet::ExecutionFailure
          raise Puppet::Error.new(output)
          return nil
        end   # begin
      else
        debugline "invalid package, skipping : (#{$1}) extracted from (#{data})"
      end   # if
    }   # each



    # install the new package
    self.install

    debugline "finished"
  end   # def


  ##### latest command/method
      # Parameters needed:
      #   :name
      #   :source
      # Parameters/Value returned:
      #   :ensure   = returns version # of source package.

  def latest
    debugline "finding version on #{@resource[:source]}"

    sourcever = query
    foundver  = "0"

    # Force that a .tbz file is referenced, and not something else which can go weird.
    if @resource[:source] =~ /\.tbz$/

      # Call pkginfo on the source package (maybe updated!)
      cmdline = ["-qf", @resource[:source] ]
      begin
        output = pkginfo(*cmdline)
      rescue Puppet::ExecutionFailure
        raise Puppet::Error.new(output)
        return nil
      end

      # cycle through all the packfile output and get the @name variable
      output.split("\n").each { |line|
        if line =~ /^@name \S+-([^-\s]+)$/
          foundver = $1
        end   # if
      }   # each

      return foundver 

    else
      Puppet.err "source is not a .tbz file - setting version to (#{sourcever[:ensure]})"
      return sourcever[:ensure]
    end   # if


  end   #   def

end   # package/provider

