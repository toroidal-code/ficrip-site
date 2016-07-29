//=require 'common'

$(document).ready(function(){
  var theme = $('meta[name=theme]').attr('content');
  var color = theme === 'light' ? 'white' : 'black';

  // These are forward-references for the
  // handlers of the links on the page.
  var advancedlinkHandler = null;
  var simplelinkHandler = null;
  var aboutlinkHandler = null;

  var afterLoad = function() {
    $('.tooltipped').tooltip();
    // Reset the handlers
    $('#advanced-link').click(advancedlinkHandler);
    $('#simple-link').click(simplelinkHandler);
    $('#about-link').click(aboutlinkHandler);
    $(':submit').click(formSubmit($('#simple-form')));
  };

  var loadAdvancedScript = function() {
    $.ajax('assets/advanced.js', {
      dataType: "script",
      error: function() { window.location = '/advanced' }
    });
  };

  // Advanced-link AJAX event
  advancedlinkHandler = function (event) {
    event.preventDefault();

    var successCallback = function (data) {
      $('main').add('#advanced-link').fadeOut(600).promise().done(function() {
        $('#main-row').replaceWith(data);
        loadAdvancedScript();
        afterLoad();
        $('main').add('#simple-link').fadeIn(650);
      });
    };

    $.ajax("/advanced", {
      data: { style: theme },
      success: successCallback,
      error: function () { window.location = '/advanced' }
    });
  };

  // #simple-link AJAX event
  simplelinkHandler = function (event) {
    event.preventDefault();

    var successCallback = function (data) {
      $('main').add('#simple-link').fadeOut(600).promise().done(function() {
        $('#main-row').replaceWith(data);
        $('main').add('#advanced-link').fadeIn(650);
        $('.tooltipped').tooltip();
      });
    };

    // Send the AJAX request
    $.ajax("/simple", {
      data: { style: theme },
      success: successCallback,
      error: function () { window.location = '/simple' }
    });
  };

  var previousMain = null;
  var previousFooter = null;
  var backlinkHandler = null;

  // The click() event handler for the about-link
  aboutlinkHandler = function (event) {
    event.preventDefault();

    // The function to call on success of the AJAX request
    var successCallback = function (data) {
      $('body').fadeOut(750, function () {
        // Save the old elements for if we want to go back
        previousMain = $('main').html();
        previousFooter = $('footer').html();

        // Replace the primary container
        $('.container').replaceWith(data);

        // Replace the footer
        $('footer').html(
          '<footer class="page-footer ' + color + '" style="margin-top: unset; padding-top: unset;">' +
          '  <div class="footer-copyright ' + color + '">' +
          '    <div class="container center-align">' +
          '      <a id="back-link" href="javascript:;" class="grey-text">back</a>' +
          '    </div>' +
          '  </div>' +
          '</footer>'
        );

        // Set up the event handler for the back link
        $('#back-link').click(backlinkHandler);
      }).fadeIn(750); // Fade in after everything's done
    };

    // The actual AJAX request for the about page
    $.ajax("/about", {
      data: { style: theme },
      success: successCallback,
      error: function () { window.location = '/about' }
    });
  };

  // Restore previous state on clicking 'back'
  backlinkHandler = function () {
    $('body').fadeOut(750, function () {
      $('main').html(previousMain);
      $('footer').html(previousFooter);
      afterLoad();
    }).fadeIn(750);
  };

  afterLoad();
});
