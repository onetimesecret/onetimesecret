<?php
  include('onetimesecret-api.php');
  $myOnetime = new OneTimeSecret;
  $myOnetime->setRecipient('delano@onetimesecret.com');
  $myOnetime->setTTL(7200);
  $myOnetime->setCustomerID('chris@onetimesecret.com');
  $myOnetime->setToken('4dc74a03fwr9aya5qur5wa8vavo4gih1hasj6181');
  $myResult = $myOnetime->shareSecret("Jazz, jazz and more jazz.", 'thepassword'));
  print $myOnetime->getSecretURI($myResult);
  print "\n\n";
?>
