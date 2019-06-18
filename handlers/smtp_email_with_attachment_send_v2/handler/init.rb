# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class SmtpEmailWithAttachmentSendV2
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
    server                  = @info_values["server"]
    port                    = @info_values["port"]
    tls                     = to_bool(@info_values["tls"])
    from                    = @info_values["from"]
    username                = @info_values["username"]
    password                = @info_values["password"]
    enable_debug_logging    = @info_values["enable_debug_logging"]
    to                      = @parameters["to"]
    cc                      = @parameters["cc"]
    bcc                     = @parameters["bcc"]
    display_name            = @parameters["display_name"]
    reply_to                = @parameters["reply_to"]
    subject                 = @parameters["subject"]
    htmlbody                = @parameters["htmlbody"]
    textbody                = @parameters["textbody"]
    attachment_file_name    = @parameters["attachment_file_name"]
    attachment_file_content = @parameters["attachment_file_content"]
    attachment_encoding     = @parameters["attachment_encoding"]

    Mail.defaults do
      delivery_method :smtp, {
        :address              => server,
        :port                 => port,
        :user_name            => username,
        :password             => password,
        :authentication       => "plain",
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

    mail.attachments[attachment_file_name] = attachment_file_content

    mail.deliver

    <<-RESULTS
    <results>
      <result name="Message Id">#{escape(mail.message_id)}</result>
    </results>
    RESULTS

    rescue Exception => error
      raise StandardError, error
  end


  ##############################################################################
  # General handler utility functions
  ##############################################################################

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
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