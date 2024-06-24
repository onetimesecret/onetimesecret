
$(function() {
  $.fn.deobfuscate = function() {
    $(this).each(function(i, el) {
      var email, subject;
      // Use textContent to avoid HTML/script injection attacks.
      // e.g. Instead of using innerHTML.
      email = el.textContent;
      email = email.replace(/ at /gi, "@").replace(/ dot /gi, ".");
      subject = el.getAttribute('data-subject');
      // Encode subject to ensure it's safe for use in URL
      subject = subject ? ("?subject=" + encodeURIComponent(subject)) : "";
      email = '<a href="mailto:'+encodeURIComponent(email)+subject+'">'+email+'</a>';
      // Clear the existing text content
      el.textContent = '';
      // Since we're now inserting a safe anchor tag, using innerHTML here is acceptable
      el.innerHTML = email;
    });
    return this;
  };
});


// COMMON BEHAVIORS
$(function() {
  $('#secreturi').select();
  $(".selectable").click(function(){
    this.select();
  });
  $('.email').deobfuscate();

  $('#contentTab a').click(function (e) {
    e.preventDefault();
    window.location.hash = this.hash + '-tab';
    e.preventDefault();
    $(this).tab('show');
  });
});
