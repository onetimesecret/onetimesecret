
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
  $(".selectable").click(function(){
    this.select();
  });
  $('.email').deobfuscate();
  $('#optionsToggle').click(function(){
    $('#options').toggle();
  });
});
