import React, { PropTypes } from "react";
import {
  OverlayTrigger,
  Popover
} from "react-bootstrap";
import _ from "lodash";

class ChooserPopover extends React.Component {
  constructor( props ) {
    super( props );
    this.state = {
      choices: props.choices,
      current: 0
    };
  }

  componentWillReceiveProps( newProps ) {
    this.setState( {
      current: this.state.choices.indexOf( newProps.chosen || newProps.defaultChoice )
    } );
  }

  chooseCurrent( ) {
    const currentChoice = this.state.choices[this.state.current];
    // Dumb, but I don't see a better way to explicity close the popover
    $( "body" ).click( );
    if ( currentChoice ) {
      this.props.setChoice( currentChoice );
    } else {
      this.props.clearChoice( );
    }
  }

  render( ) {
    const {
      container,
      chosen,
      defaultChoice,
      className,
      preIconClass,
      postIconClass,
      label,
      hideClear,
      choiceIconClass
    } = this.props;
    return (
      <OverlayTrigger
        trigger="click"
        placement="bottom"
        rootClose
        container={container}
        overlay={
          <Popover className="ChooserPopover RecordChooserPopover">
            <ul className="list-unstyled">
              { hideClear ? null : (
                <li
                  className={this.state.current === -1 ? "current" : ""}
                  onMouseOver={( ) => {
                    this.setState( { current: -1 } );
                  }}
                  onClick={( ) => this.chooseCurrent( )}
                  className="pinned"
                  style={{ display: this.props.chosen ? "block" : "none" }}
                >
                  <i className="fa fa-times"></i>
                  { _.capitalize( I18n.t( "clear" ) ) }
                </li>
              ) }
              { _.map( this.state.choices, ( s, i ) => (
                <li
                  key={`source-chooser-source-${s}`}
                  className={ `media ${this.state.current === i ? "current" : ""}` }
                  onClick={( ) => this.chooseCurrent( )}
                  onMouseOver={( ) => {
                    this.setState( { current: i } );
                  }}
                >
                  <div className="media-left">
                    { choiceIconClass ? <i className={`media-object ${choiceIconClass}`}></i> : null }
                  </div>
                  <div className="media-body">
                    { I18n.t( s ) }
                  </div>
                </li>
              ) ) }
            </ul>
          </Popover>
        }
      >
        <div
          className={
            `ChooserPopoverTrigger RecordChooserPopoverTrigger ${chosen ? "chosen" : ""} ${className}`
          }
        >
          { preIconClass ? <i className={`${preIconClass} pre-icon`}></i> : null }
          { label ? ( <label>{ label }</label> ) : null }
          { I18n.t( chosen || defaultChoice ) }
          { postIconClass ? <i className={`${postIconClass} post-icon`}></i> : null }
        </div>
      </OverlayTrigger>
    );
  }
}

ChooserPopover.propTypes = {
  container: PropTypes.object,
  chosen: PropTypes.string,
  choices: PropTypes.array,
  defaultChoice: PropTypes.object,
  className: PropTypes.string,
  setChoice: PropTypes.func,
  clearChoice: PropTypes.func,
  preIconClass: PropTypes.oneOfType( [PropTypes.string, PropTypes.bool] ),
  postIconClass: PropTypes.oneOfType( [PropTypes.string, PropTypes.bool] ),
  label: PropTypes.string,
  hideClear: PropTypes.bool,
  choiceIconClass: PropTypes.string
};

ChooserPopover.defaultProps = {
  preIconClass: "fa fa-search",
  choices: []
};

export default ChooserPopover;
