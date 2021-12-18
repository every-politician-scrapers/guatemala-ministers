#!/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'pry'
require 'scraped'
require 'table_unspanner'
require 'wikidata_ids_decorator'

require 'open-uri/cached'

class RemoveReferences < Scraped::Response::Decorator
  def body
    Nokogiri::HTML(super).tap do |doc|
      doc.css('sup.reference').remove
    end.to_s
  end
end

class UnspanAllTables < Scraped::Response::Decorator
  def body
    Nokogiri::HTML(super).tap do |doc|
      doc.css('table.wikitable').each do |table|
        unspanned_table = TableUnspanner::UnspannedTable.new(table)
        table.children = unspanned_table.nokogiri_node.children
      end
    end.to_s
  end
end

class MinistersList < Scraped::HTML
  decorator RemoveReferences
  decorator UnspanAllTables
  decorator WikidataIdsDecorator::Links

  field :ministers do
    member_entries.map { |ul| fragment(ul => Officeholder).to_h }
                  .reject { |row| row[:name].to_s.empty? }
  end

  private

  def member_entries
    noko.xpath('//table[.//th[contains(.,"Mandato")]]//tr[td]')
  end
end

class Officeholder < Scraped::HTML
  field :wdid do
    tds[2].css('a/@wikidata').first
  end

  field :name do
    tds[2].text.tidy
  end

  field :position do
    tds[0].text.tidy
  end

  private

  def tds
    noko.css('td')
  end
end

url = 'https://es.wikipedia.org/wiki/Gabinete_de_Alejandro_Giammattei'
data = MinistersList.new(response: Scraped::Request.new(url: url).response).ministers

header = data.first.keys.to_csv
rows = data.map { |row| row.values.to_csv }
abort 'No results' if rows.count.zero?

puts header + rows.join
