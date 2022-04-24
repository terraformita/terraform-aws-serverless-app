'use strict';

class App extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      friends: [],
      name: '',
      id: '',
      notes: '',
      /* API PREFIX */
      apiPrefix: '/dev'
    };

    this.create = this.create.bind(this);
    this.update = this.update.bind(this);
    this.delete = this.delete.bind(this);
    this.handleChange = this.handleChange.bind(this);
  }

  componentDidMount() {
    // get all entities - GET
    // fetch("/api/friend/friendModel", {
    //   "method": "GET",
    //   "headers": {
    //     "x-rapidapi-host": "fairestdb.p.rapidapi.com",
    //     "x-rapidapi-key": API_KEY
    //   }
    // })
    //   .then(response => response.json())
    //   .then(response => {
    //     this.setState({
    //       friends: response
    //     })
    //   })
    //   .catch(err => {
    //     console.log(err);
    //   });
  }

  create(e) {
    // add entity - POST
    e.preventDefault();

    // creates entity
    fetch(this.state.apiPrefix + "/api/friend/friendModel", {
      "method": "POST",
      "headers": {
        "x-rapidapi-host": "fairestdb.p.rapidapi.com",
        "content-type": "application/json",
        "accept": "application/json"
      },
      "body": JSON.stringify({
        name: this.state.name,
        notes: this.state.notes
      })
    })
      .then(response => response.json())
      .then(response => {
        console.log(response)
      })
      .catch(err => {
        console.log(err);
      });
  }

  update(e) {
    // update entity - PUT
    e.preventDefault();

    // this will update entries with PUT
    fetch(this.state.apiPrefix + "/api/friend/friendModel", {
      "method": "PUT",
      "headers": {
        "x-rapidapi-host": "fairestdb.p.rapidapi.com",
        "content-type": "application/json",
        "accept": "application/json"
      },
      "body": JSON.stringify({
        _id: this.state.id,
        name: this.state.name,
        notes: this.state.notes
      })
    })
      .then(response => response.json())
      .then(response => {
        console.log(response);
      })
      .catch(err => { console.log(err); });
  }

  delete(e) {
    // delete entity - DELETE
    e.preventDefault();
    // deletes entities
    fetch(this.state.apiPrefix + `/api/friend/friendModel/_id/${this.state.id}`, {
      "method": "DELETE",
      "headers": {
        "x-rapidapi-host": "fairestdb.p.rapidapi.com",
      }
    })
      .then(response => response.json())
      .then(response => {
        console.log(response);
      })
      .catch(err => {
        console.log(err);
      });
  }

  handleChange(changeObject) {
    this.setState(changeObject)
  }

  render() {
    return (
      <div className="container">
        <div className="row justify-content-center">
          <div className="col-md-8">
            <h1 className="display-4 text-center">Make An API Call in React</h1>
            <form className="d-flex flex-column">
              <legend className="text-center">Add-Update-Delete Friend</legend>
              <label htmlFor="name">
                Friend Name:
                <input
                  name="name"
                  id="name"
                  type="text"
                  className="form-control"
                  value={this.state.name}
                  onChange={(e) => this.handleChange({ name: e.target.value })}
                  required
                />
              </label>
              <label htmlFor="notes">
                Friend notes:
                <input
                  name="notes"
                  id="notes"
                  type="test"
                  className="form-control"
                  value={this.state.notes}
                  onChange={(e) => this.handleChange({ notes: e.target.value })}
                  required
                />
              </label>
              <label htmlFor="id">
                Friend ID:
                <input
                  name="id"
                  id="id"
                  type="text"
                  className="form-control"
                  value={this.state.id}
                  onChange={(e) => this.handleChange({ id: e.target.value })}
                />
              </label>
              <button className="btn btn-primary" type='button' onClick={(e) => this.create(e)}>
                Add
              </button>
              <button className="btn btn-info" type='button' onClick={(e) => this.update(e)}>
                Update
              </button>
              <button className="btn btn-danger" type='button' onClick={(e) => this.delete(e)}>
                Delete
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
