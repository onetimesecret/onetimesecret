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

function postAndRefresh(e) {
  var obj = $(this);
  $.ajax({
    type: 'POST',
    url: obj.attr('href'),
    data: {'shrimp': shrimp},
    success: function(data, textStatus){
      //log(data)
      window.location.reload()
    },
    error: function(){
      //alertify.error("Ooops! There was an error.")
    }
  });
  return e.preventDefault();
};

function postAndRedirect(e) {
  var obj = $(this);
  log(obj.attr('href'))
  $.ajax({
    type: 'POST',
    url: obj.attr('href'),
    data: {'shrimp': shrimp},
    success: function(data, textStatus){
      window.location = '/';
    },
    error: function(){
      //alertify.error("Ooops! There was an error.")
    }
  });
  return e.preventDefault();
};

function postAndIgnore(e) {
  var obj = $(this);
  $.ajax({
    type: 'POST',
    url: obj.attr('href'),
    data: {'shrimp': shrimp},
    success: function(data, textStatus){
      //alertify.log("Updated")
      window.location.reload()
    },
    error: function(){
      //alertify.error("Ooops! There was an error.")
    }
  });
  return e.preventDefault();
};

// COMMON BEHAVIORS
$(function() {
  $('.entropy-generate').click(postAndRefresh);
  $('input.clearDefault').clearDefault();
  $('#secreturi').select();
  $(".selectable").click(function(){
    this.select();
  });
  $('.email').deobfuscate();
  $('#optionsToggle').click(function(){
    $('#options').toggle();
    $.cookie("display_options", $('#options').css('display') == 'block');
  });
  if ($.cookie("display_options") == "true") {
    $('#options').toggle();
  }
  $( "#primaryTabs" ).tabs();
});
