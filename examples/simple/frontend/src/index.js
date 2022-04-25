'use strict';

const config = {
  apiPrefix: '/dev'
};

class App extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      info: {
        application: "",
        version: ""
      },
      config: config,
    };
  }

  getApiInfo(e) {
    e.preventDefault();

    fetch(this.state.config.apiPrefix + "/api/info", {
      "method": "GET",
      "headers": {
        "accept": "application/json"
      }
    })
      .then(response => response.json())
      .then(response => {
        this.setState({
          info: response
        })
      })
      .catch(err => {
        console.log(err);
      });
  }

  componentDidMount() {
  }

  handleChange(changeObject) {
    this.setState(changeObject)
  }

  render() {
    return (
      <div className="container">
        <div className="row justify-content-center">
          <div className="col-md-8">
            <h1 className="display-4 text-center">Simple API-backed React Page</h1>
            <form className="d-flex flex-column">
              <legend className="text-center">API Info Will Show Up Below.</legend>
              {this.state.info.application !== "" ? <legend className="text-center">Application: {this.state.info.application}. Version: {this.state.info.version}</legend> : null}
              <button className="btn btn-primary" type='button' onClick={(e) => this.getApiInfo(e)}>
                Get API Info
              </button>
            </form>
          </div>
        </div>
      </div>
    );
  }
}

let domContainer = document.querySelector('#App');
ReactDOM.render(<App />, domContainer);
