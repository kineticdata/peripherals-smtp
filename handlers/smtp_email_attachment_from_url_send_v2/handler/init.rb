# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class SmtpEmailAttachmentFromUrlSendV2

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
    
    # Determine if debug logging is enabled
    @debug_logging_enabled = @info_values['enable_debug_logging'] == 'Yes'
    puts("Logging enabled.") if @debug_logging_enabled

  end

  def execute()

    server                  = @info_values["server"]
    port                    = @info_values["port"]
    tls                     = to_bool(@info_values["tls"])
    from                    = @info_values["from"]
    username                = @info_values["username"]
    password                = @info_values["password"]
    to                      = @parameters["to"]
    cc                      = @parameters["cc"]
    bcc                     = @parameters["bcc"]
    display_name            = @parameters["display_name"]
    reply_to                = @parameters["reply_to"]
    subject                 = @parameters["subject"]
    htmlbody                = @parameters["htmlbody"]
    textbody                = @parameters["textbody"]
    attachment_file_name    = @parameters["attachment_file_name"]
    attachment_encoding     = @parameters["attachment_encoding"]
    attachment_url          = @parameters["attachment_url"]

    # Wrap the exeute method in a begin/rescue block so that error messages can
    # be chosen to be raised like normal or returned in the results Xml
    begin
      # begin

      Mail.defaults do
        delivery_method :smtp, {
          :address              => server,
          :port                 => port,
          :user_name            => username.to_s.strip.empty? ? nil : username,
          :password             => password.to_s.strip.empty? ? nil : password,
          :authentication       => username.to_s.strip.empty? ? nil : "plain",
          :enable_starttls_auto => tls
        }
      end
  
      mail = Mail.new do
        from          "#{display_name} <#{from}>"
        to            "#{to}"
        cc            "#{cc}"
        bcc           "#{bcc}"
        "reply-to"    "#{reply_to}"
        subject       "#{subject}"
  
        text_part do
          body "#{textbody}"
        end
  
        html_part do
          content_type "text/html; charset=UTF-8"
          body "#{htmlbody}"
        end
  
        content_transfer_encoding "#{attachment_encoding}"
      end
  
      io = open(attachment_url)

      mail.attachments[attachment_file_name] = {
        :content => io.read 
      }
  
      mail.deliver

      # Build and return the results
      results = "<results>\n"
      results += "  <result name='Message Id'>#{escape(mail.message_id)}</result>\n"
      results += "  <result name='Success'>true</result>\n"
      results += "  <result name='Error Message'></result>\n"
      results += "</results>"
    rescue Exception => e
      if to_bool(@parameters['raise_errors'])
        raise
      else
        results = "<results>\n"
        results += "  <result name='Message Id'></result>\n"
        results += "  <result name='Success'>false</result>\n"
        results += "  <result name='Error Message'>#{escape(e.message)}</result>\n"
        results += "</results>"
      end
    end
    puts "Results:\n#{results}" if @debug_logging_enabled
    return results
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(arg)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    arg.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] }
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}

  # Helper method to convert "True" and "False" to actual boolean values.
  def to_bool(string)
    return true   if string == true   || string =~ (/(true|t|yes|y|1)$/i)
    return false  if string == false  || string.empty? || string =~ (/(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{string}\"")
  end
end