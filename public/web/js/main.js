
/* NOTE: Disable cufon to resolve issues displaying utf-8 characters
// Font Replacement
// Cufon.replace('.cufon');
*/

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
  //$('#optionsToggle').click(function(){
  //  $('#options').toggle();
  //  $.cookie("display_options", $('#options').css('display') == 'block');
  //});
  // if ($.cookie("display_options") == "true") {
  //   $('#options').toggle();
  // }

  $('#contentTab a').click(function (e) {
    e.preventDefault();
    window.location.hash = this.hash + '-tab';
    e.preventDefault();
    $(this).tab('show');
  });
});

