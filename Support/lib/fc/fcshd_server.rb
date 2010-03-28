#!/usr/bin/env ruby
# encoding: utf-8

require 'webrick'
require 'net/http'
require 'fileutils'

#Running as daemon
require 'rubygems'
require 'daemons'
require 'logger'

# Useful URLs for debugging via your web browser.
# http://localhost:6924/info
# http://localhost:6924/exit
# http://localhost:6924/status
#
# Notes: I removed all the exit calls on the s.mount_proc blocks - to what seems
# like no detrimental effect because they were being caught as an error by the 
# Webrick::HTTPServer (see the webrick_log_file).
#
# Zombies suck so I figured usig Daemons.daemonize(:mulitple => false) would be 
# a safer option but it appears to leave 'variable @controller_argv not initialized'
# errors in the system.log file.
#
module FCSHD_SERVER
  
  class << self
    
    PORT = 6924
    HOST = "localhost"

    ASSIGNED_REGEXP = /^ fcsh:.*(\d+).*/ 
    
    def log_file
      "#{ENV['HOME']}/Library/Logs/TextMate\ FCSHD.log"
    end
    
    def webrick_log_file
      "#{ENV['HOME']}/Library/Logs/TextMate\ Webrick\ FCSHD.log"
    end

    #remembering wich swfs we asked for compiling
    def start_server
      
      Daemons.daemonize(:mulitple => false) 
      
      @commands = Hash.new if @commands.nil?
      
      log = Logger.new(log_file)
      log.info("Initializing server")
      
    	fcsh = ::IO.popen("#{ENV['TM_FLEX_PATH']}/bin/fcsh  2>&1", "w+")
    	read_to_prompt(fcsh)

    	#Creating the HTTP Server  
    	s = WEBrick::HTTPServer.new(
    		:Port => PORT,
    		:Logger => WEBrick::Log.new(webrick_log_file, WEBrick::BasicLog::DEBUG), #WARN
    		:AccessLog => []
    	)

    	#giving it an action
    	s.mount_proc("/build"){|req, res|

    		#response variable
    		output = ""
    		
    		#Searching for an id for this command
    		if @commands.has_key?(req.body)
    			# Exists, incremental
    			fcsh.puts "compile #{@commands[req.body]}"
    			output = read_to_prompt(fcsh)
    		else
    			# Does not exist, compile for the first time
    			fcsh.puts req.body
    			output = read_to_prompt(fcsh)
    			match = output.scan(ASSIGNED_REGEXP)
    			@commands[req.body] = match[0][0]
    		end
    		
    		log.debug("asked: #{req.body}")
    		log.debug("output: #{output}")

    		res.body = output
    		res['Content-Type'] = "text/html"
    	}

    	s.mount_proc("/exit"){|req, res|
    	  log.debug("shutting down")
        s.shutdown
        fcsh.puts "quit"
        sleep 0.2
        fcsh.close
    	}
    	
    	s.mount_proc("/status"){|req, res|
    	  log.debug("getting status")
    		res.body = "UP"
    	}
    	 
      s.mount_proc("/info"){|req, res|
        log.debug("getting info")
        fcsh.puts 'info'
        output = read_to_prompt(fcsh)
        res.body = output
        res['Content-Type'] = "text/html"
      }

    	trap("INT"){
    		s.shutdown
    		fcsh.close
    	}

      #Starting webrick
      log.info("Starting Webrick at http://#{HOST}:#{PORT}")
      
      begin
        
        s.start
        
      rescue Exception => e
        
        #Do not show error if we're trying to start the server more than once
        if e.message =~ /Address already in use/ < 0
          log.debug(e.message)
        else
          log.debug(e)
        end
        
      end
      
      log.info("Closed Webrick at http://#{HOST}:#{PORT}")

      #cleanly quit the daemon.
      exit
      
    end

    #Helper method to read output
    def read_to_prompt(f)
    	f.flush
    	output = ""
    	while chunk = f.read(1)
    		STDOUT.write chunk
    		output << chunk
    		if output =~ /^\(fcsh\)/
    			break
    		end
    	end
    	STDOUT.write ">"
    	output
    end
    
    def build(what)
      # puts arg
      http = Net::HTTP.new(HOST, PORT)
      resp, date = http.post('/build', what)
      resp.body
    end
    
    def stop_server
      #If you're seeing an error in the system log this could explain why...
      #http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-core/2578
      #I resolved by changing 'resp, date = http.get...' to 'resp = http.get...'
      http = Net::HTTP.new(HOST, PORT)
      resp = http.get('/exit')
      resp.body
    end
    
    def running
      begin
        http = Net::HTTP.new(HOST, PORT)
        resp, date = http.get('/status', nil) {
          return true
        }
      rescue => e
        puts "Error #{e}" unless e.message =~ /Connection refused - connect\(2\)/ #msql connection problem... apparently.
        return false
      end
      
      return false
    end
    
  end
  
end
