
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
  $.fn.clearDefault = function(){
    return this.each(function(){
      var default_value = $(this).val();
      $(this).focus(function(){
        if ($(this).val() == default_value) $(this).val("");
      });
      $(this).blur(function(){
        if ($(this).val() == "") $(this).val(default_value);
      });
    });
  };
  $.fn.mustache = function (data, partial, stream) {
    var content = Mustache.to_html(this.html(), data, partial, stream)
    this.replaceWith(content);
    $(this)
  };
});

function generateEntropy(e) {
  var obj = $(this);
  obj.text(obj.attr('alt'));
  obj.click(function(e) {
    e.preventDefault();
  });
  $.ajax({
    type: 'POST',
    url: obj.attr('href'),
    data: {'shrimp': shrimp},
    success: function(data, textStatus){
      window.location.reload()
    },
    error: function(){
      alertify.error("Ooops! There was an error.")
    }
  });
  return e.preventDefault();
};

// COMMON BEHAVIORS
$(function() {
  $('.entropy-generate').click(generateEntropy);
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
