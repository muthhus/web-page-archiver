# encoding: utf-8
# generate mhtml file 
# == uri target uri
# return mhtml file
#mhtml = WebPageArchiver::MhtmlGenerator.generate("https://rubygems.org/")
#open("output.mht", "w+"){|f| f.write mhtml }
module WebPageArchiver
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'digest/md5'
require 'stringio'
require 'base64'
require 'thread'
require 'mime/types'

  module GeneratorHelpers
    def initialize
      @contents = {}
      @src = StringIO.new
      @boundary = "mimepart_#{Digest::MD5.hexdigest(Time.now.to_s)}"
      @threads  = []
      @queue    = Queue.new
      @conf     = { :base64_except=>["html"]}
    end
    def join_uri(base_filename_or_uri, path)
      stream = open(base_filename_or_uri)
      joined = ""
      if stream.is_a? File
        joined = URI::join("file://#{base_filename_or_uri}", path)
        joined = joined.to_s.gsub('file://','').gsub('file:','')
      else
        joined = URI::join(base_filename_or_uri, path)
      end
      return joined.to_s
    end
    def content_type(f)
      if f.is_a? File
        return MIME::Types.type_for(f.path).first
      else
        return f.meta["content-type"]
      end
    end
    def start_download_thread(num=5)
      num.times{
        t = Thread.start{
          while(@queue.empty? == false)
            k = @queue.pop
            next if @contents[k][:body] != nil
            v = @contents[k][:uri]
            f = open(v)
            @contents[k] = @contents[k].merge({ :body=>f.read, :uri=> v, :content_type=> content_type(f) })
          end
        }
        @threads.push t
      }
      return @threads
    end
    def download_finished?
      @contents.find{|k,v| v[:body] == nil } == nil
    end
  end

# == generate mhtml (mht) file 
#
# mhtml = WebPageArchiver::MhtmlGenerator.generate("https://rubygems.org/")
# open("output.mht", "w+"){|f| f.write mhtml }
  class MhtmlGenerator
    include GeneratorHelpers
    attr_accessor :conf
    def MhtmlGenerator.generate(uri)
      generateror = MhtmlGenerator.new
      return generateror.convert(uri)
    end
    def convert(filename_or_uri)
        f = open(filename_or_uri)
        html = f.read
        @parser = Nokogiri::HTML html
        @src.puts "Subject: " + @parser.search("title").text()
        @src.puts "Content-Type: multipart/related; boundary=#{@boundary}"
        @src.puts "Content-Location: #{filename_or_uri}"
        @src.puts "Date: #{Time.now.to_s}"
        @src.puts "MIME-Version: 1.0"
        @src.puts ""
        @src.puts "mime mhtml content"
        @src.puts ""
        #imgs
        @parser.search('img').each{|i| 
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri).to_s
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('src',"cid:#{uid}")
          }
        #styles
        @parser.search('link[rel=stylesheet]').each{|i|
            uri = i.attr('href');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('href',"cid:#{uid}")
          }
        #scripts
        @parser.search('script').map{ |i|
            next unless i.attr('src');
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('src',"cid:#{uid}")
        }
        @src.puts "--#{@boundary}"
        @src.puts "Content-Disposition: inline; filename=default.htm"
        @src.puts "Content-Type: #{content_type(f)}"
        @src.puts "Content-Id: #{Digest::MD5.hexdigest(filename_or_uri)}"
        @src.puts "Content-Location: #{filename_or_uri}"
        @src.puts "Content-Transfer-Encoding: 8bit" if @conf[:base64_except].find("html")
        @src.puts "Content-Transfer-Encoding: Base64" unless @conf[:base64_except].find("html")
        @src.puts ""
        #@src.puts html
        @src.puts "#{html}"                      if @conf[:base64_except].find("html")
        #@src.puts "#{Base64.encode64(html)}" unless @conf[:base64_except].find("html")
        @src.puts ""
        self.attach_contents
        @src.puts "--#{@boundary}--"
        @src.rewind
        return @src.read
    end
    def attach_contents
      #prepeare_queue
      @contents.each{|k,v| @queue.push k}
      #start download threads
      self.start_download_thread
      # wait until download finished.
      @threads.each{|t|t.join}
      @contents.each{|k,v|self.add_html_content(k)}
    end
    def add_html_content(cid)
      filename = File.basename(URI(@contents[cid][:uri]).path)
      @src.puts "--#{@boundary}"
      @src.puts "Content-Disposition: inline; filename=" + filename 
      @src.puts "Content-Type: #{@contents[cid][:content_type]}"
      @src.puts "Content-Location: #{@contents[cid][:uri]}"
      @src.puts "Content-Transfer-Encoding: Base64"
      @src.puts "Content-Id: #{cid}"
      @src.puts ""
      @src.puts "#{Base64.encode64(@contents[cid][:body])}"
      @src.puts ""
       return
    end
  end


  # == generate self-containing data-uri based html file (html) file 
  #
  # mhtml = WebPageArchiver::DataUriHtmlGenerator.generate("https://rubygems.org/")
  # open("output.html", "w+"){|f| f.write mhtml }
    class DataUriHtmlGenerator
      include GeneratorHelpers
      
      attr_accessor :conf
      def DataUriHtmlGenerator.generate(uri)
        generateror = DataUriHtmlGenerator.new
        return generateror.convert(uri)
      end

      def convert(filename_or_uri)
          @parser = Nokogiri::HTML(open(filename_or_uri))
          @parser.search('img').each{|i| 
              uri = i.attr('src');
              uri = join_uri( filename_or_uri, uri).to_s
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
              i.set_attribute('src',"cid:#{uid}")
            }
          #styles
          @parser.search('link[rel=stylesheet]').each{|i|
              uri = i.attr('href');
              uri = join_uri( filename_or_uri, uri)
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'href'}
              i.set_attribute('href',"cid:#{uid}")
            }
          #scripts
          @parser.search('script').map{ |i|
              next unless i.attr('src');
              uri = i.attr('src');
              uri = join_uri( filename_or_uri, uri)
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
              i.set_attribute('src',"cid:#{uid}")
          }
          self.set_contents
          return @parser.to_s
      end

      def set_contents
        #prepeare_queue
        @contents.each{|k,v| @queue.push k}
        #start download threads
        self.start_download_thread
        # wait until download finished.
        @threads.each{|t|t.join}
        @contents.each do |k,v|
          content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
          tag=v[:parser_ref]
          attribute=v[:attribute_name]
          content_type=v[:content_type]
          tag.set_attribute(attribute,"data:#{content_type};base64,#{content_benc}")
        end
      end
      
    end


    # == generate self-containing all-inline html file (html) file 
    #
    # mhtml = WebPageArchiver::InlineHtmlGenerator.generate("https://rubygems.org/")
    # open("output.html", "w+"){|f| f.write mhtml }
    class InlineHtmlGenerator
      include GeneratorHelpers
      
      attr_accessor :conf
      def InlineHtmlGenerator.generate(uri)
        generateror = InlineHtmlGenerator.new
        return generateror.convert(uri)
      end

      def convert(filename_or_uri)
          @parser = Nokogiri::HTML(open(filename_or_uri))
          @parser.search('img').each{|i| 
              uri = i.attr('src');
              uri = join_uri( filename_or_uri, uri).to_s
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
              i.set_attribute('src',"cid:#{uid}")
            }
          #styles
          @parser.search('link[rel=stylesheet]').each{|i|
              uri = i.attr('href');
              uri = join_uri( filename_or_uri, uri)
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'href'}
              i.set_attribute('href',"cid:#{uid}")
            }
          #scripts
          @parser.search('script').map{ |i|
              next unless i.attr('src');
              uri = i.attr('src');
              uri = join_uri( filename_or_uri, uri)
              uid = Digest::MD5.hexdigest(uri)
              @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
              i.set_attribute('src',"cid:#{uid}")
          }
          self.set_contents
          return @parser.to_s
      end

      def set_contents
        #prepeare_queue
        @contents.each{|k,v| @queue.push k}
        #start download threads
        self.start_download_thread
        # wait until download finished.
        @threads.each{|t|t.join}
        @contents.each do |k,v|
          tag=v[:parser_ref]
          if tag.name == "script"
            content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
          
            attribute=v[:attribute_name]
            content_type=v[:content_type]
            tag.content=v[:body]
            tag.remove_attribute(v[:attribute_name])
          elsif tag.name == "link" and v[:content_type]="text/css"
            tag.after("<style type=\"text/css\">#{v[:body]}</style>")
            tag.remove()
          else
            # back to inline
            content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
            attribute=v[:attribute_name]
            content_type=v[:content_type]
            tag.set_attribute(attribute,"data:#{content_type};base64,#{content_benc}")
            
          end
        end
      end
      
    end

end
