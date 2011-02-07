Puppet::Type.type(:rcconf).provide :freebsd do

  desc "Provider for rcconf configuration items using built in ruby/puppet commands."

  confine :operatingsystem => [:freebsd]

  ##### Ensurable methods:
      #   enabled?    = check to see if value is set
      #   enable      = create the key/value pair
      #   disable     = delete the key/value pair

  # boolean check to see if it's set
  def enabled?  
    # exec: "sysrc -n -i :name" - return value means it's there
    if output
      Puppet.debug("sysrc found: #{output}")
      :true
    end
    Puppet.debug("sysrc didn't find a value for #{:name}")
    :false
  end

  def enable
    # Create the key with the corresponding value
    # exec: "sysrc [-f ":rcfile"] key=value
    Puppet.debug("Creating key/value pair")
  end

  def disable
    # Remove the corresponding key
    # exec: "sysrc -x [-f ":rcfile"] key
    Puppet.debug("Delete key/value pair")
  end


----- old code follows:


  @@rcconf = '/etc/rc.conf'
  @@rcconf_local = '/etc/rc.conf.local'
  @@rcconf_dir = '/etc/rc.conf.d'

  def self.defpath
    superclass.defpath
  end

  # Executing an init script with the 'rcvar' argument returns
  # the service name, rcvar name and whether it's enabled/disabled
  def rcvar
    rcvar = execute([self.initscript, :rcvar], :failonfail => true, :squelch => false)
    rcvar = rcvar.split("\n")
    rcvar.delete_if {|str| str =~ /^#\s*$/}
    rcvar[1] = rcvar[1].gsub(/^\$/, '')
    rcvar
  end

  # Extract service name
  def service_name
    name = self.rcvar[0]
    self.error("No service name found in rcvar") if name.nil?
    name = name.gsub!(/# (.*)/, '\1')
    self.error("Service name is empty") if name.nil?
    self.debug("Service name is #{name}")
    name
  end

  # Extract rcvar name
  def rcvar_name
    name = self.rcvar[1]
    self.error("No rcvar name found in rcvar") if name.nil?
    name = name.gsub!(/(.*)_enable=(.*)/, '\1')
    self.error("rcvar name is empty") if name.nil?
    self.debug("rcvar name is #{name}")
    name
  end

  # Extract rcvar value
  def rcvar_value
    value = self.rcvar[1]
    self.error("No rcvar value found in rcvar") if value.nil?
    value = value.gsub!(/(.*)_enable="?(\w+)"?/, '\2')
    self.error("rcvar value is empty") if value.nil?
    self.debug("rcvar value is #{value}")
    value
  end

  # Edit rc files and set the service to yes/no
  def rc_edit(yesno)
    service = self.service_name
    rcvar = self.rcvar_name
    self.debug("Editing rc files: setting #{rcvar} to #{yesno} for #{service}")
    self.rc_add(service, rcvar, yesno) if not self.rc_replace(service, rcvar, yesno)
  end

  # Try to find an existing setting in the rc files
  # and replace the value
  def rc_replace(service, rcvar, yesno)
    success = false
    # Replace in all files, not just in the first found with a match
    [@@rcconf, @@rcconf_local, @@rcconf_dir + "/#{service}"].each do |filename|
      if File.exists?(filename)
        s = File.read(filename)
        if s.gsub!(/(#{rcvar}_enable)=\"?(YES|NO)\"?/, "\\1=\"#{yesno}\"")
          File.open(filename, File::WRONLY) { |f| f << s }
          self.debug("Replaced in #{filename}")
          success = true
        end
      end
    end
    success
  end

  # Add a new setting to the rc files
  def rc_add(service, rcvar, yesno)
    append = "\# Added by Puppet\n#{rcvar}_enable=\"#{yesno}\"\n"
    # First, try the one-file-per-service style
    if File.exists?(@@rcconf_dir)
      File.open(@@rcconf_dir + "/#{service}", File::WRONLY | File::APPEND | File::CREAT, 0644) {
        |f| f << append
        self.debug("Appended to #{f.path}")
      }
    else
      # Else, check the local rc file first, but don't create it
      if File.exists?(@@rcconf_local)
        File.open(@@rcconf_local, File::WRONLY | File::APPEND) {
          |f| f << append
          self.debug("Appended to #{f.path}")
        }
      else
        # At last use the standard rc.conf file
        File.open(@@rcconf, File::WRONLY | File::APPEND | File::CREAT, 0644) {
          |f| f << append
          self.debug("Appended to #{f.path}")
        }
      end
    end
  end

  def enabled?
    if /YES$/ =~ self.rcvar_value
      self.debug("Is enabled")
      return :true
    end
    self.debug("Is disabled")
    :false
  end

  def enable
    self.debug("Enabling")
    self.rc_edit("YES")
  end

  def disable
    self.debug("Disabling")
    self.rc_edit("NO")
  end

  def startcmd
    [self.initscript, :onestart]
  end

  def stopcmd
    [self.initscript, :onestop]
  end

  def statuscmd
    [self.initscript, :onestatus]
  end

end