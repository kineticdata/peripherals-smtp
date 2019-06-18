# Require the necessary core libraries.
require 'java'
require 'rexml/document'
require 'date'
require 'digest'

# Determine the path to the handler
handler_path = File.expand_path(File.dirname(__FILE__))

# Require the dependencies file to load the vendor libraries
require File.join(handler_path, 'ics_event_invite_send_handler_helper')

# Require the necessary java libraries
require File.join(handler_path, 'lib', 'smtp.jar')
require File.join(handler_path, 'lib', 'mailapi.jar')
require File.join(handler_path, 'lib', 'commons-email-1.2.jar')

# If we are using a Java prior to 1.6, where the necessary files became included
# in the standard library, manually include the activation.jar.
if java.lang.System.getProperty('java.class.version').to_i < 50
  # Require the activation jar
  require File.join(handler_path, 'lib', 'activation.jar')
  # If we are using Java 1.6 or later, implement a JRuby classpath fix for Email
else
  # There is a problem with the JRuby classloading when using Java 6 that
  # prevents the proper Mime mappings from being retrieved.  This is a
  # workaround to fix the classpath used by org.apache.commons.mail.HtmlEmail
  # during send.
  org.apache.commons.mail.MultiPartEmail.module_eval do
    # Alias the original 'send' method name to 'send_without_jruby_fix'
    alias_method :send_without_jruby_fix, :send
    # Redefine the send method
    def send()
      # Spawn a new thread so that we are not manipulating the current classloader
      thread = Thread.new do
        # Overwrite the current classloader
        java.lang.Thread.currentThread().setContextClassLoader(java_class.class_loader)
        # Call the old send method
        Thread.current['kinetic/task/IcsEventInviteSendV1/result'] = send_without_jruby_fix()
      end
      # Wait for the thread to complete
      thread.join
      # Return the thread result
      return thread['kinetic/task/IcsEventInviteSendV1/result']
    end
  end
end