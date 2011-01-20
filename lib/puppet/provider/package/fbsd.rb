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
    to the full package origin (eg: ftp/wget for wget application).  This provider
    does not auto-install dependencies, nor error if they're not found on install."

  # Operating restrictions/Suitability requirements
  # defaultfor :operatingsystem => :freebsd   # uncomment when approved by someone important
  confine   :operatingsystem => :freebsd
  commands  :pkgadd   => "/usr/sbin/pkg_add",
            :pkginfo  => "/usr/sbin/pkg_info",
            :pkgdel   => "/usr/sbin/pkg_delete",
            :pkgver   => "/usr/sbin/pkg_version"

  # Provider/Package Methods that need to be built. (+ = completed)
  # info types:
  # ! instances - build list of hashs of all installed packages, return list
  # ! query - build hash of specified package details, return hash
  #   latest - find latest version of software available, return string
  # action types:
  # ! install - install a package
  # ! uninstall - uninstall a package
  # + update - update an installed software package - only
  #   purge - purge software including all configuration/etc.

  ##### Instances command - builds list of installed packages
      # fields to populate:
      #   :ensure       - package version
      #   :name         - package name (internal name to Freebsd ie: port origin)
      #   :description  - package shortname (what it's commonly called)

  def self.instances
    Puppet.debug "fbsd.instances : Building installed package list"

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
        Puppet.debug "fbsd.instances : skipped dataline #{dataline}"
      end
    } # output.split

    # Return package listing
    return packages

  end   # def instances



  ##### Installation Command
      # Fields required/used:
      #   :name     = package origin to install
      #   :ensure   = version of the package to install (if a choice)
      #   :source   = the package file/URL
      #   

  def install
    Puppet.debug "fbsd.install : Installing Package (#{@resource[:name]}"

    # Force that a .tbz file is referenced, and not something else which can go weird.
    if @resource[:source] =~ /\.tbz$/

      # Call pkgadd to get installed listing
      cmdline = ["--verbose", "--no-deps", @resource[:source]]
      begin
        output = pkgadd(*cmdline)
      rescue Puppet::ExecutionFailure
        raise Puppet::Error.new(output)
        return nil
      end
    else
      raise Puppet::Error, "Package source file does not end with .tbz: #{@resource[:source]}"
    end   # if
  end   # def



  ##### Query Command
      # Fields required/used:
      #   :name
      #   :ensure
      #   :description

  def query
    Puppet.debug "fbsd.query : query made on #{@resource[:name]}"

    hash = Hash.new

    # Call pkginfo on the source package (maybe updated!)
    cmdline = ["-oQ", @resource[:name] ]
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
      Puppet.debug "fbsd.query : ERROR : output can't be parsed (#{output})"
      return nil
    end   # if
  
    # Return 'nil' since we shouldn't get here.
    return nil
  end   # def

    
  ##### uninstall command/method
      # Fields required/used
      #   :name

  def uninstall
    Puppet.debug "fbsd.uninstall : called for #{@resource[:name]}"

    # Get full package name from port origin to uninstall with
    cmdline = ["-qO", @resource[:name]]
    begin
      output = pkginfo(*cmdline)
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new(output)
    end

    output.split("\n").each { |data|
      if data =~ /^(\S+)$/
        # uninstall the package
        Puppet.debug "fbsd.uninstall : removing #{data}"
        cmdline = [ "--verbose", $1 ]
        begin
          output = pkgdel(*cmdline)
        rescue Puppet::ExecutionFailure
          raise Puppet::Error.new(output)
          return nil
        end   # begin
      else
        Puppet.debug "fbsd.uninstall : invalid package, skipping : #{$1} : #{data}"
      end   # if
    }   # each

  end   # def


  ##### update command/method
      # Fields required/used
      #   :name
      #   :source
      #   

  def update
    Puppet.debug "fbsd.update : called for #{@resource[:name]}"

    # uninstall the old package
    self.uninstall

    # install the new package
    self.install

  end   # def


  ##### latest command/method
      # Fields required/used
      #   :name
      #   :source
      #

  def latest
    Puppet.debug "fbsd.latest : returning source version"

    sourcever = nil

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
        sourcever = $1
      end   # if
    }   # each

    return sourcever
  end   #   def

end   # package/provider

