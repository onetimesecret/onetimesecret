function OptionsToggle() {
  var myElement = document.getElementById("options");
  if(myElement.style.display == "block") {
      myElement.style.display = "none";
  }
  else {
      myElement.style.display = "block";
  }
}

// COMMON BEHAVIORS
$(function() {  
  $("#secreturi").focus(function(){
    this.select();
  });
});