#!/usr/bin/ruby

#
# Zypper patch reporter. Inspired by both apticron and porticron.
#
# Tested on Ruby 2.0. Make sure you install rubygem-nokogiri rubygem-erubis
#
# (C) 2014 vjt@openssl.it - MIT License
#
require 'nokogiri'
require 'erubis'
require 'ostruct'
require 'open3'

class XmlParser < OpenStruct
  def initialize(xml)
    super()
    @xml = xml
  end

  protected
    def xml(xpath)
      @xml.xpath(xpath)
    end

    def text(xpath)
      xml(xpath).text
    end

    def flag(xpath)
      text(xpath) == 'true'
    end
end

class Update < XmlParser

  def initialize(xml)
    super

    self.name        = text('./@name')
    self.status      = text('./@status')
    self.category    = text('./@category')
    self.arch        = text('./@arch')
    self.edition     = text('./@edition')
    self.summary     = text('./summary')
    self.description = text('./description')

    self.pkgmanager  = flag('./@pkgmanager')
    self.restart     = flag('./@restart')
    self.interactive = flag('./@interactive')

    self.source      = Source.new xml('./source')

    self.freeze
  end

  class Source < XmlParser
    def initialize(xml)
      super

      self.name = text('./@alias')
      self.url  = text('./@url')
      self.freeze
    end
  end

end

def run!(command, description)
  Open3.popen3(*command) do |_, stdout, stderr, guard|
    out = Thread.new { stdout.read }.value
    err = Thread.new { stderr.read }.value

    if guard.value.exitstatus == 0

      if err.strip.size > 0
        puts "#{command.join(' ')}: #{err}"
      end
      return out

    else
      puts "= #$hostname: Error while #{description}"
      puts err
      puts out
      exit 1
    end
  end
end

# Main
$hostname = `hostname -f`.chomp

# Try refreshing the repositories
run! ['zypper', 'ref'], 'refreshing repositories'

# OK, get list of patches
run! ['zypper', '-x', 'lp'], 'fetching patches list'

source = File.popen('zypper -x lp').read
updates = Nokogiri.parse(source).xpath('//update').map {|xml| Update.new(xml)}

exit 0 if updates.size == 0

categories = updates.inject(Hash.new(0)) {|h, update| h[update.category] += 1; h}

# Render
puts Erubis::Eruby.new(DATA.read).result(binding)

__END__
= <%= $hostname %>: <%= updates.size %> updates available =

<% categories.each do |category, count| %>
  * <%= count %> <%= category %> updates
<% end %>

<% updates.group_by(&:source).each do |source, updates| %>
  == <%= updates.size %> updates from <%= source.name %> (<%= source.url %>)
  <% updates.each do |update| %>
    * <%= update.name %> - <%= update.status %>: <%= update.summary %>
  <% end %> 
<% end %>


Details
-------------------------------------------------
<% updates.each do |update| %>

=== <%= update.name %>: edition <%= update.edition %>

<% if update.restart %>
==== Requires reboot
<% end %>
<% if update.interactive %>
==== Cannot be run unattended
<% end %>
<% if update.pkgmanager %>
==== Softwarestack upgrade: re-run the update afterwards
<% end %>
<%= update.description.strip.gsub(/^\s+/m, '') %>
<% end %>
