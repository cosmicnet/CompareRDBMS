/*
 *
 * Main JavaScript functions utilising the JQuery framework
 *
 */


// Load JS once the rest of the page has finished loading
$(document).ready(function() {

    /*
     * Routines for the DBMS configuration
     */

    // Ajax call to DB config test function
    $('#test_btn').click( function () {
        $('#test_results').html('<img src="http://img.cdn.tl/loading51.gif" width=30 height=30/>');
        $.post(
            'compare.cgi',
            $('#config_form').serialize().replace('rm=dbms_save','rm=dbms_test'),
            function (response) {
                if ( response.success ) {
                    // Set green colour
                    $('#test_results').css('background-color', '#AAFFAA');
                    $('#test_results').html('ok');
                }
                else {
                    // Set red colour
                    $('#test_results').css('background-color', '#FFAAAA');
                    $('#test_results').html(response.error);
                }
            },
            'json'
        );
    });
    // Reset test results on form change
    $('#config_form').change( function () {
        // Remove colour
        $('test_results').html('');
    });

    // Generate a sample dsn
    $('#dsn_btn').click( function () {
        var dsn = dsn_sample.replace( '{db}', $('#db').val() ).replace( '{host}', $('#host').val() );
        $('#dsn').val( dsn );
    });


    /*
     * Routines for the profile type configuration
     */

    // Create/Edit type
    $('input[name=create], input[name=edit]', '#profile_details').click( function () {
        var $table = $(this).closest('table');
        var profile = $(this).attr('data-profile');
        // Backup input values
        $('.standard .pro_' + profile + ' input', $table).each( function () {
            $(this).attr( 'data-value', $(this).val() );
        });
        $('.extended .pro_' + profile + ' input', $table).each( function () {
            $(this).attr( 'data-value', $(this).val() );
        });
        // Enable the inputs
        $('.pro_' + profile + ' input', $table).removeAttr('disabled');
        // Show the save button and hide the create
        $(this).siblings('input[name=save]').show();
        $(this).siblings('input[name=delete]').hide();
        $(this).siblings('input[name=cancel]').attr( 'data-button', $(this).attr('name') ).show();
        $(this).hide();
    });

    // Cancel create/edit type
    $('input[name=cancel]', '#profile_details').click( function () {
        var $table = $(this).closest('table');
        var profile = $(this).attr('data-profile');
        // Restore inputs
        $('.standard .pro_' + profile + ' input', $table).each( function () {
            $(this).val( $(this).attr( 'data-value' ) );
        });
        $('.extended .pro_' + profile + ' input', $table).each( function () {
            $(this).val( $(this).attr( 'data-value' ) );
        });
        // Disable the inputs
        $('.standard .pro_' + profile + ' input', $table).attr('disabled','disabled');
        $('.extended .pro_' + profile + ' input', $table).attr('disabled','disabled');
        // Show the create/edit button and hide the create
        if ( $(this).attr('data-button') == 'create' ) {
            $(this).siblings('input[name=create]').show();
        }
        else {
            $(this).siblings('input[name=edit]').show();
            $(this).siblings('input[name=delete]').show();
        }
        $(this).siblings('input[name=save]').hide();
        $(this).hide();
    });

    // Save type
    $('input[name=save]', '#profile_details').click( function () {
        // Get local vars for elements as *this* is subject to change
        var $table = $(this).closest('table');
        var $delete = $(this).siblings('input[name=delete]');
        var $edit = $(this).siblings('input[name=edit]');
        var $cancel = $(this).siblings('input[name=cancel]');
        var $save = $(this);
        var profile = $(this).attr('data-profile');
        var type = $table.attr('data-type');
        // Gather the standard details
        var standard = {};
        $('.standard .pro_' + profile + ' input', $table).each( function () {
            standard[ $(this).attr('name') ] = $(this).val();
        });
        // Gather the extended details
        var extended = {};
        $('.extended .pro_' + profile + ' input', $table).each( function () {
            extended[ $(this).attr('name') ] = $(this).val();
        });
        // Put into an object
        var type_details = {
            standard: standard,
            extended: extended
        };

        $.post(
            '/compare.cgi',
            {
                rm: 'profile_detail_save',
                profile: profile,
                type: type,
                JSONDATA: JSON.stringify( type_details )
            },
            function (response) {
                // All good?
                if ( response.success ) {
                    alert('Save successful');
                    // Show/hide buttons
                    $delete.show();
                    $edit.show();
                    $cancel.hide();
                    $save.hide();
                    // Disable the inputs
                    $('.standard .pro_' + profile + ' input', $table).attr('disabled','disabled');
                    $('.extended .pro_' + profile + ' input', $table).attr('disabled','disabled');
                }
                else {
                    alert( response.error );
                }
            },
            'json'
        );
    });

    // Delete type
    $('input[name=delete]', '#profile_details').click( function () {
        // Get elements
        var $table = $(this).closest('table');
        var $buttons = $(this).parent().children('input');
        var $create = $(this).siblings('input[name=create]');
        // Get the profile ID and type
        var profile = $(this).attr('data-profile');
        var type = $table.attr('data-type');

        // Confirm the delete
        if ( confirm('Are you sure you want to delete this type?') ) {
            $.post(
                '/compare.cgi',
                {
                    rm: 'profile_detail_save',
                    profile: profile,
                    type: type,
                    delete: 1
                },
                function (response) {
                    // All good?
                    if ( response.success ) {
                        alert('Delete successful');
                        // Make sure only create is showing
                        $buttons.hide();
                        $create.show();
                        // Clear and disable the inputs
                        $('.standard .pro_' + profile + ' input', $table).val('').attr('disabled','disabled');
                        $('.extended .pro_' + profile + ' input', $table).val('').attr('disabled','disabled');
                    }
                    else {
                        alert( response.error );
                    }
                },
                'json'
            );
        }
    });

});
