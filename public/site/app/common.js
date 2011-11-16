function OptionsToggle() {
  var myElement = document.getElementById("options");
  if(myElement.style.display == "block") {
      myElement.style.display = "none";
  }
  else {
      myElement.style.display = "block";
  }
}

$(function() {  
  $.fn.deobfuscate = function() {
    $(this).each(function(i, el) {
      var email, subject;
      email = el.innerHTML;
      email = email.replace(/ at /gi, "@").replace(/ dot /gi, ".");
      subject = el.getAttribute('data-subject');
      subject = subject ? ("?subject=" + subject) : ""
      email = '<a href="mailto:'+email+subject+'">'+email+'</a>';
      el.innerHTML = email;
    });
    return this;
  };
});


// COMMON BEHAVIORS
$(function() {  
  $("#secreturi").focus(function(){
    this.select();
  });
  $('.email').deobfuscate();
});
