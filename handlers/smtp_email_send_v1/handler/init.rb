require 'erb'

# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class SmtpEmailSendV1
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
  end

  # The execute method gets called by the task engine when the handler's node is processed. It is
  # responsible for performing whatever action the name indicates.
  # If it returns a result, it will be in a special XML format that the task engine expects. These
  # results will then be available to subsequent tasks in the process.
  def execute
    error_handling = @parameters["error_handling"]

    begin
      server                  = @info_values["server"]
      port                    = @info_values["port"]
      tls                     = to_bool(@info_values["tls"])
      username                = @info_values["username"].to_s.strip
      password                = @info_values["password"]
      from                    = @parameters["from"]
      to                      = @parameters["to"]
      subject                 = @parameters["subject"]
      htmlbody                = @parameters["htmlbody"]
      textbody                = @parameters["textbody"]

      mail_options = {
        :address              => server,
        :port                 => port,
        :enable_starttls_auto => tls
      }
      if username.size > 0
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
    end
  end


  ##############################################################################
  # General handler utility functions
  ##############################################################################

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
end