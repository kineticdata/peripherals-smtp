require 'erb'
#require 'dotenv'
#require 'dotenv/editor'
require 'net/http'
require 'uri'
require "base64"

# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class SmtpEmailSendV2
  # Prepare for execution by building Hash objects for necessary values and
  # validating the present state.  This method sets the following instance
  # variables:
  # * @input_document - A REXML::Document object that represents the input Xml.
  # * @info_values - A Hash of info names to info values.
  # * @parameters - A Hash of parameter names to parameter values.
  #
  # This is a required method that is automatically called by the Kinetic Task
  # Engine.
  #
  # ==== Parameters
  # * +input+ - The String of Xml that was built by evaluating the node.xml
  #   handler template.
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end
    
    #Build endpoints for OAUTH

  end

  # The execute method gets called by the task engine when the handler's node is processed. It is
  # responsible for performing whatever action the name indicates.
  # If it returns a result, it will be in a special XML format that the task engine expects. These
  # results will then be available to subsequent tasks in the process.
  def execute
    error_handling = @parameters["error_handling"]
    @log_level = @info_values['log_level'] || 'info'

    begin
      server                  = @info_values["server"]
      authtype                = @info_values["authtype"].downcase
      username                = @info_values["username"].to_s.strip
      password                = @info_values["password"]
      port                    = @info_values["port"]
      from                    = @parameters["from"]
      to                      = @parameters["to"] || []
      cc                      = @parameters["cc"] || []
      bcc                     = @parameters["bcc"] || []
      subject                 = @parameters["subject"]
      htmlbody                = @parameters["htmlbody"]
      textbody                = @parameters["textbody"]

      ####Decide which method and compose email
      case authtype
      when "basic" || "plain"
        log( "Basic/Plain auth selected")
        #Overwrite from with smtp_from_address if from is NOT provided - used for relay
        from                    = @info["smtp_from_address"] if from.nil? || from.strip.empty?
        mail_options = {
          :delivery_method      => :smtp,
          :address              => server,
          :port                 => port,
          :enable_starttls_auto => to_bool(@info_values["tls"])
        }
        if !username.empty?
          mail_options[:user_name] = username
          mail_options[:password] = password
          mail_options[:authentication] = "plain"
        end
        Mail.defaults do
          delivery_method :smtp, mail_options
        end
        mail = Mail.new do
          from          "#{from}"
          to            "#{to}"
          bcc           "#{bcc}"
          subject       "#{subject}"

          text_part do
            body "#{textbody}"
          end
        end

        # Embed linked images into the html body if present
        unless htmlbody.nil? || htmlbody.empty?
          # Initialize a hash of image links to embeded values
          embedded_images = {}

          # Iterate over the body and embed necessary images
          htmlbody.scan(/"cid:(.*)"/) do |match|
            # The match variable is an array of Regex groups (specified with
            # parentheses); in this case the first match is the url
            url = match.first
            # Unless we have already embedded this url
            unless embedded_images.has_key?(url)
              cid = embed_url(mail,url)
              embedded_images[url] = cid
            end
          end

          # Replace the image URLs with their embedded values
          embedded_images.each do |url, cid|
            htmlbody.gsub!(url, cid)
          end

          mail.html_part do
            content_type "text/html; charset=UTF-8"
            body "#{htmlbody}"
          end
        end

        mail.deliver

        <<-RESULTS
        <results>
          <result name="Message Id">#{ERB::Util.html_escape(mail.message_id)}</result>
        </results>
        RESULTS
      when "graph"
        log( "graph selected","debug")
        tenant_id = @info_values['tenant_id']
        payload = {
          message: {
            subject: subject,
            body: {
              contentType: "HTML",
              content: htmlbody
            },
            toRecipients: 
             Array(to).flat_map { |v| v.split(',') }
               .map(&:strip)
               .reject(&:empty?)
               .map { |email| { emailAddress: { address: email } }
            },
            ccRecipients: 
              Array(cc).flat_map { |v| v.split(',') }
               .map(&:strip)
               .reject(&:empty?)
               .map { |email| { emailAddress: { address: email } }
            },
            bccRecipients: 
              Array(bcc).flat_map { |v| v.split(',') }
               .map(&:strip)
               .reject(&:empty?)
               .map { |email| { emailAddress: { address: email } }
            }
          },
          attachments: [
            #{
            #  "@odata.type": "#microsoft.graph.fileAttachment",
            #  "name": "attachment.txt",
            #  "contentType": "text/plain",
            #  "contentBytes": "SGVsbG8gV29ybGQh"
            #}
          ],
          saveToSentItems: true
        }
        log( "Payload created", "debug")
        MicrosoftGraphEmail(from,tenant_id,username,password,payload)
      end
      <<-RESULTS
      <results>
        <result name="Completed">Complete</result>
      </results>
      RESULTS
    rescue Exception => error
      if error_handling == "Raise Error"
        raise error
      else
        <<-RESULTS
        <results>
          <result name="Handler Error Message">#{ERB::Util.html_escape(error.inspect)}</result>
        </results>
        RESULTS
      end
    ensure
    end

  end


  ##################
  # MAIL FUNCTIONS
  ##################


  def MicrosoftGraphEmail(from,tenant_id,client_id,client_secret,payload)
    access_token = MSAccessToken(tenant_id, client_id, client_secret)
    log("Acces token retrieved","debug")
    sendURI = URI("https://graph.microsoft.com/v1.0/users/#{from}/sendMail")
    
    req = Net::HTTP::Post.new(sendURI)
    req['Authorization'] = "Bearer #{access_token}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(payload)
    res = Net::HTTP.start(sendURI.hostname, sendURI.port, use_ssl: true) { |http| http.request(req) }
    log( "POST request sent","debug")
    if res.is_a?(Net::HTTPSuccess)
      log( "Email sent successfully!","debug")
    else
      log( "Failed to send email: #{res.code} #{res.body}", "error")
    end

  end


  ##############################################################################
  # General handler utility functions
  ##############################################################################
  def MSAccessToken(tenant_id, client_id, client_secret)
    uri = URI("https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token")
    log( "URI: #{uri}")
    req = Net::HTTP::Post.new(uri)
    req.set_form_data({
      'client_id' => client_id,
      'scope' => 'https://graph.microsoft.com/.default',
      'client_secret' => client_secret,
      'grant_type' => 'client_credentials'
    })
    log( "Requesting token from Azure")
    log( "URI: #{uri.hostname} - port: #{uri.port}")
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    if res.is_a?(Net::HTTPSuccess)
      log( "Req successful - #{res}")
    else
      log( "Req failed - #{res}", "error")
      raise "Failed to get token: #{res.body}"
    end
     log( "Returning token")

    return JSON.parse(res.body)['access_token']
  end

  # Helper method to convert "True" and "False" to actual boolean values.
  def to_bool(string)
    return true   if string == true   || string =~ (/(true|t|yes|y|1)$/i)
    return false  if string == false  || string.empty? || string =~ (/(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{string}\"")
  end

  def embed_url(mail, url)
    uri = URI.parse(url)
    filename = File.basename(uri.path)

    response = RestClient.get url
    mail.attachments[filename] = { :content => response.body, :content_type => response.headers[:content_type] }
    mail.attachments[filename].content_disposition("inline; name=\"#{filename}\"")

    return mail.attachments[filename].cid
  end

  def log(message, log_level="info")
    unless @logtier
      @logtier = {"error" => 1, "debug" => 2, "info"=> 3}
    end
    
    puts "#{Time.now.utc} [#{log_level.upcase}] #{message}" if @logtier[log_level] >= @logtier[@log_level]
  end
end