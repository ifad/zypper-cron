#!/usr/bin/env ruby

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

source = File.popen('zypper -x lp').read
updates = Nokogiri.parse(source).xpath('//update').map {|xml| Update.new(xml)}

exit 0 if updates.size == 0

hostname = `hostname -f`.chomp
categories = updates.inject(Hash.new(0)) {|h, update| h[update.category] += 1; h}

# Render
puts Erubis::Eruby.new(DATA.read).result(binding)

__END__
= <%= hostname %>: <%= updates.size %> updates available =

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
