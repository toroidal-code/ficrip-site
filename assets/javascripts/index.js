$(document).ready(function(){
  var theme = $('meta[name=theme]').attr('content');
  var color = theme === 'light' ? 'white' : 'black';
  var advancedJSLoaded = false;

  // Advanced-link AJAX event
  var advancedlinkCallback = function (event) {
    event.preventDefault();
    $.ajax("/advanced", {
      data: { style: theme },
      success: function (data) {
        $('main').add('#advanced-link').fadeOut(600).promise().done(function() {
          $('#main-row').replaceWith(data);
          if (!advancedJSLoaded) {
            $.ajax('assets/advanced.js', {
              dataType: "script",
              success: function () { advancedJSLoaded = true; },
              error: function() { window.location = '/advanced' }
            });
          }
          $('main').add('#simple-link').fadeIn(650);
        });
      },
      error: function () {
        console.log('Ajax load failed; falling back to url redirection.');
        window.location = '/advanced'
      }
    });
  };
  $('#advanced-link').click(advancedlinkCallback);

  // simple-link AJAX event
  var simplelinkCallback = function (event) {
    event.preventDefault();
    $.ajax("/simple", {
      data: { style: theme },
      success: function (data) {
        $('main').add('#simple-link').fadeOut(600).promise().done(function() {
          $('#main-row').replaceWith(data);
          $('main').add('#advanced-link').fadeIn(650);
        });
      },
      error: function () {
        console.log('Ajax load failed; falling back to url redirection.');
        window.location = '/simple'
      }
    });
  };
  $('#simple-link').click(simplelinkCallback);

  var aboutlinkCallback = function (event) {
    event.preventDefault();
    $.ajax("/about", {
      data: { style: theme },
      success: function (data) {
        $('body').fadeOut(750, function () {
          previousMain = $('main').html();
          previousFooter = $('footer').html();
          $('.container').replaceWith(data);
          $('footer').html(
            '<footer class="page-footer ' + color + '" style="margin-top: unset; padding-top: unset;">' +
            '  <div class="footer-copyright ' + color + '">' +
            '    <div class="container center-align">' +
            '      <a id="back-link" href="javascript:;" class="grey-text">back</a>' +
            '    </div>' +
            '  </div>' +
            '</footer>'
          );
          $('#back-link').click(backlinkCallback);
        }).fadeIn(750);
      },
      error: function () {
        console.log('Ajax load failed; falling back to url redirection.');
        window.location = '/about'
      }
    });
  };
  $('#about-link').click(aboutlinkCallback);

  var previousMain = null;
  var previousFooter = null;

  var backlinkCallback = function () {
    $('body').fadeOut(750, function () {
      $('main').html(previousMain);
      $('footer').html(previousFooter);

      // Reset the handlers
      $('#advanced-link').click(advancedlinkCallback);
      $('#simple-link').click(simplelinkCallback);
      $('#about-link').click(aboutlinkCallback);
    }).fadeIn(750);
  };

  // simple-link AJAX event

});