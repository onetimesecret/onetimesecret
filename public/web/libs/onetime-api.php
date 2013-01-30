<?php

/**
 * One-Time Secret API v1. This requires an account and API key on https://onetimesecret.com/ to use. 
 *
 * @package OneTimeSecret
 */

class OneTimeSecret {

    var $APIToken;
    var $theHostname = 'onetimesecret.com';
    var $APIVersion = 'v1';
    var $APIURI = 'https://onetimesecret.com/api/v1/';
    var $customerID;
    var $privateKey;
    var $secretKey;
    var $secretTTL = 3600;
    var $theRecipient;

    /**
     * Validate email addresses
     * 
     * @access private
     * @param string $emailAddress an email address to be validated
     * @return true if the email address is valid, false otherwise
     */
    private function validateEmail($emailAddress) {
        $emailRegex = '/^[A-z0-9][\w.-]*@[A-z0-9][\w\-\.]+\.[A-z0-9]{2,6}$/';
        $valid = false;
        $valid = preg_match($emailRegex, $emailAddress);
        return $valid;
    }

    /**
     * Make the actual REST API call 
     * 
     * @access private
     * @param array $postdata Parameters required for the given API call
     * @return JSON formatted response code
     */
    private function APIRequest ($postdata) {

        $postdata = http_build_query($postdata);    

        $options = array('http' => array(
                                'method' => 'POST',
                                'header' => 'Authorization: Basic ' . base64_encode($this->customerID.':'.$this->APIToken) ."\r\n"
                                          . "Content-Type: text/html; charset=utf-8\r\n"
                                          . "Content-type: application/x-www-form-urlencoded\r\n"
                                          . 'Content-Length: ' . strlen($postdata) . "\r\n",
                                'content' => $postdata));

        $context = stream_context_create($options);
        return file_get_contents($this->APIURI,false,$context);

    }

    /**
     * Set the URI for the REST API call. 
     * 
     * @access private
     * @param string $uri The REST API method to be called ('share' or 'generate' for now)
     * @return true 
     */
    private function setURI ($method) {

        if(($method == 'generate') or ($method == 'share')) {
            $this->APIURI = 'https://' . $this->theHostname . '/api/' . $this->APIVersion . '/'. $method;
        }
        else {
            return false; //invalid method
        }
        return true;
    }


    /**
     * Set the hostname for the API call. 
     * 
     * @access public
     * @param string $theHostname The FQDN for the REST API 
     * @return true if it's a valid hostname.
     */
    public function setHostname ($theHostname) {

        $hostnameRegex = '/^[A-z0-9][\w\-\.]+\.[A-z0-9]{2,6}$/';
        if (preg_match($hostnameRegex, $theHostname)) {
            $this->theHostname = $theHostname;
            return true;
        }
        else {
            return false;
        }
    }

    /**
     * Set the recipient value. 
     * 
     * @access public
     * @param string $emailAddress The email address of the recipient
     * @return true if it's a valid email address.
     */
    public function setRecipient ($emailAddress) {
        if($this->validateEmail($emailAddress)) {
            $this->theRecipient = $emailAddress;
            return true;
        }
        else{
            return false;
        }
    }


    /**
     * Set the TTL value. Won't allow any value less than 3600, which is the minimum.
     * This is how much time, in seconds, the secret URI will be valid for.
     * 
     * @access public
     * @param string $ttl The desired TTL
     * @return void
     */
    public function setTTL($ttl) {
        if(intval($ttl) < 3600) { $ttl = 3600; } //1 hour minimum
        $this->secretTTL = intval($ttl);
    }


    /**
     * Set the customerid value. This is part of the required authentication for
     * API access. The customerid is usually the email address you used to sign up
     * and use to login to https://onetimesecret.com/
     * 
     * @access public
     * @param string $customerID The customerid 
     * @return true if it's a valid email address.
     */
    public function setCustomerID ($customerID) {
        if($this->validateEmail($customerID)) {
            $this->customerID = $customerID;
            return true;
        }
        else{
            return false;
        }
    }

    /**
     * Set the api token value. This is part of the required authentication for
     * API access. To get your token, login to https://onetimesecret.com/ and 
     * go to the account page. At the bottom of the page is a button to generate 
     * your API token. 
     * 
     * @access public
     * @param string $token The api token 
     * @return true if it only contains a-f, 0-9
     */
    public function setToken ($token) {

        $valid = false;
        $valid = preg_match('|^[a-f0-9]*$|i', $token);

        if($valid) {
            $this->APIToken = $token;
        }
    }

    /**
     * Share a secret by using the 'share' REST API call. 
     * 
     * @access public
     * @param string $secret The secret to be shared 
     * @param string $passphrase An optional passphrase
     * @return string returns the JSON response from the server
     */
    public function shareSecret($secret, $passphrase = '') {

        $postdata = array ('secret'     => $secret, 
                           'passphrase' => $passphrase,
                           'ttl'        => $this->secretTTL,
                           'recipient'  => $this->theRecipient);

        $this->setURI('share');
        return $this->APIRequest($postdata);
    
    }

    /**
     * Share a generated secret by using the 'generate' REST API call. 
     * 
     * @access public
     * @param string $passphrase An optional passphrase
     * @return string returns the JSON response from the server
     */
    public function generateSecret ($passphrase = '') {

        $postdata = array ('passphrase' => $passphrase,
                           'ttl'        => $this->secretTTL,
                           'recipient'  => $this->theRecipient);

        $this->setURI('generate');
        return $this->APIRequest($postdata);
    
    }

    /**
     * Return a URI for the private metadata
     *
     * @jsonResult string $jsonResult The JSON result returned by an API call
     * @return string a standard URL
     */
    public function getPrivateURI ($jsonResult) {

        $myResult = json_decode($jsonResult, true);
        return 'https://'.$this->theHostname.'/private/'.$myResult['metadata_key']; 

    }

    /**
     * Return a URI for the secret (what the recipient needs to load)
     *
     * @jsonResult string $jsonResult The JSON result returned by an API call
     * @return string a standard URL
     */
    public function getSecretURI ($jsonResult) {

        $myResult = json_decode($jsonResult, true);
        return 'https://'.$this->theHostname.'/secret/'.$myResult['secret_key']; 

    }
}
?>
